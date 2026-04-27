//
//  PromptDatabase.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//


import Foundation

// MARK: - Prompt Database
/// Single source of truth for ALL prompts in the entire app
struct PromptDatabase {
    
    enum PromptKey: String {
        // Phase 1 - Creator Analysis
        case a1a_structuralSpine = "a1a_structural_spine"
        case a1b_beatExtraction = "a1b_beat_extraction"
        case a2_mechanicsFingerprint = "a2_mechanics_fingerprint"
        case a2_qualityScoring = "a2_quality_scoring"
        case a3_aggregation = "a3_aggregation"
        
        // Add future prompts here as you build them
        // case w1_outline = "w1_outline"
        // case w4_section_draft = "w4_section_draft"
    }
    
    /// Get a prompt with variable substitution
    static func get(_ key: PromptKey, variables: [String: String] = [:]) -> String {
        var prompt = getPromptTemplate(key)
        
        // Replace {{variable}} with values
        for (key, value) in variables {
            prompt = prompt.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        
        return prompt
    }
    
    // MARK: - Prompt Templates
    
    private static func getPromptTemplate(_ key: PromptKey) -> String {
        switch key {
        case .a1a_structuralSpine:
            return """
            You are analyzing a YouTube video transcript to extract its structural spine.

            TRANSCRIPT:
            {{transcript}}

            VIDEO METADATA:
            Title: {{title}}
            Duration: {{duration}} seconds

            Extract the following:

            1. SECTIONS WITH ROLES
            Identify 3-8 major sections. For each section:
            - Time range (start-end in seconds)
            - Role (HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, SPONSORSHIP)
            - Goal (what this section accomplishes)

            IMPORTANT ROLES:
            - HOOK: Generate curiosity, establish question
            - SETUP: Provide context, establish stakes
            - EVIDENCE: Build case with data, stories, authority
            - TURN: Subvert expectations, reveal insight
            - PAYOFF: Deliver on hook's promise
            - CTA: Call to action
            - SPONSORSHIP: Sponsorship/ad read (don't remove, just flag it)

            2. LOGIC SPINE (Causal Chain)
            Map how each section builds on the previous:
            - What claim/question does HOOK establish?
            - How does SETUP build on HOOK?
            - What does EVIDENCE prove (that was set up)?
            - What does TURN reveal (that EVIDENCE enabled)?
            - How does PAYOFF deliver on HOOK's promise?

            3. BRIDGE POINTS
            Identify 1-3 sentences that belong to TWO sections (transitions).

            OUTPUT FORMAT (strict JSON):
            {
              "sections": [
                {
                  "id": "sect_1",
                  "timeRange": {"start": 0, "end": 45},
                  "role": "HOOK",
                  "goal": "Generate curiosity about...",
                  "logicSpineStep": "Claims that X causes Y"
                }
              ],
              "logicSpine": {
                "chain": ["HOOK claims X→Y", "SETUP introduces Z",...],
                "causalLinks": [
                  {"from": "sect_1", "to": "sect_2", "connection": "HOOK's question → SETUP's context"}
                ]
              },
              "bridgePoints": [
                {
                  "text": "But here's where it gets interesting...",
                  "belongsTo": ["sect_1", "sect_2"],
                  "timestamp": 43
                }
              ]
            }

            IMPORTANT:
            - Be precise with time ranges (no overlaps)
            - Logic spine must be complete causal chain
            - If there's a sponsorship, mark it as role "SPONSORSHIP"
            - Return ONLY valid JSON, no markdown formatting
            """
            
        case .a1b_beatExtraction:
            return """
            You are analyzing a section from a transcript to extract beat sequences.

            SECTION DATA:
            {{section_json}}

            FULL TRANSCRIPT CONTEXT:
            {{transcript}}

            For this section, extract:

            1. BEAT SEQUENCE
            Break the section into 2-6 beats. For each beat:
            - Type (TEASE, QUESTION, PROMISE, DATA, STORY, AUTHORITY, SYNTHESIS, TURN, etc.)
            - Time range within section
            - Text content
            - Function (what this beat accomplishes)

            2. TRANSITION TYPE
            How does this section connect to the next?
            - callback, direct_pivot, contrarian_flip, question_bridge, etc.

            3. ANCHOR LINES
            2-6 sentences that are distinctively "this creator" - not generic phrases.

            OUTPUT FORMAT (strict JSON):
            {
              "sectionId": "sect_1",
              "beats": [
                {
                  "type": "TEASE",
                  "timeRange": {"start": 0, "end": 15},
                  "text": "Here's something shocking...",
                  "function": "Generate curiosity via unexpected claim"
                }
              ],
              "transitionOut": {
                "type": "callback",
                "bridgeSentence": "But here's where it gets interesting..."
              },
              "anchorLines": [
                "And that's when things got weird.",
                "Here's the part that broke my brain."
              ]
            }

            BEAT TYPES REFERENCE:
            - TEASE: Create curiosity/tension
            - QUESTION: Rhetorical or genuine question
            - PROMISE: What you'll deliver
            - DATA: Statistics, facts, numbers
            - STORY: Narrative example
            - AUTHORITY: Expert quote, study citation
            - SYNTHESIS: "Here's what this means"
            - TURN: Subvert expectation, reveal
            - CALLBACK: Reference earlier point
            - CTA: Call to action

            Return ONLY valid JSON, no markdown formatting.
            """
            
        case .a2_mechanicsFingerprint:
            return """
            Analyze this snippet and generate its mechanics fingerprint.

            SNIPPET TEXT:
            {{snippet_text}}

            CONTEXT:
            - Section role: {{role}}
            - Beat type: {{beat_type}}
            - Section goal: {{section_goal}}

            Extract:

            1. MECHANICS ATTRIBUTES:
            - intent: (what this snippet aims to do)
            - tempo: (fast/medium/slow pacing)
            - stance: (adversarial/neutral/collaborative/authoritative)
            - tease_distance: (if applicable, sentences between promise and payoff)
            - rhetorical_devices: (list any: anaphora, metaphor, question, etc.)

            2. SENTENCE ANALYSIS:
            - sentence_count: (count)
            - avg_sentence_length: (words)
            - question_count: (count)
            - data_points: (count of statistics/facts mentioned)

            3. TOPIC:
            - primary_topic: (main subject)
            - secondary_topics: (list 0-3)
            - specificity: (general_principle/specific_example/case_study)

            4. STYLE MARKERS:
            - vocabulary_level: (1-10, where 5=average, 10=highly technical)
            - formality: (1-10, where 1=very casual, 10=very formal)
            - profanity: (true/false)
            - humor_style: (none/sarcastic/playful/dark/absurdist)
            - personal_voice: (true/false - uses "I" vs impersonal)

            5. MECHANICS DESCRIPTION (for embedding):
            Write a 1-2 sentence description of what this snippet DOES, not what it's ABOUT.
            Example: "Contrarian turn using adversarial frame, positioned early to create intrigue, fast tempo, no data points, revelation-style delivery"

            6. TOPIC DESCRIPTION (for embedding):
            Write a 1 sentence description of what this snippet is ABOUT.
            Example: "Behavioral psychology and decision-making biases"

            OUTPUT FORMAT (strict JSON):
            {
              "intent": "subvert_expectation",
              "tempo": "fast",
              "stance": "adversarial",
              "teaseDistance": null,
              "rhetoricalDevices": ["anaphora", "question"],
              "sentenceCount": 4,
              "avgSentenceLength": 12.5,
              "questionCount": 1,
              "dataPoints": 0,
              "primaryTopic": "behavioral_psychology",
              "secondaryTopics": ["decision_making", "cognitive_bias"],
              "specificity": "general_principle",
              "vocabularyLevel": 6,
              "formality": 4,
              "profanity": false,
              "humorStyle": "none",
              "personalVoice": false,
              "mechanicsDescription": "...",
              "topicDescription": "..."
            }

            Return ONLY valid JSON, no markdown formatting.
            """
            
        case .a2_qualityScoring:
            return """
            Rate this snippet's quality as a reusable example.

            SNIPPET:
            {{snippet_text}}

            MECHANICS:
            {{mechanics_json}}

            CONTEXT:
            - Beat type: {{beat_type}}
            - Role: {{role}}

            Rate as:
            - canonical: Best-in-class example, highly reusable pattern
            - situational: Useful but context-specific
            - weak: Unclear, rambling, or poor execution

            Provide:
            1. quality_tier: (canonical/situational/weak)
            2. reasoning: (2-3 sentences explaining rating)

            OUTPUT (strict JSON):
            {
              "tier": "canonical",
              "reasoning": "Perfect contrarian turn. Clear, punchy, reusable pattern."
            }

            Return ONLY valid JSON, no markdown formatting.
            """
            
        case .a3_aggregation:
            return """
            You have analyzed {{video_count}} videos from {{creator_name}}.

            AGGREGATED DATA:
            {{summary_statistics}}

            ALIGNMENT DOCS SAMPLE:
            {{alignment_docs_json}}

            SNIPPET STATISTICS:
            {{snippet_stats}}

            Extract:

            1. CREATOR MODE PROFILES (2-6 modes, not 20)
            Cluster videos by structural similarity. For each mode:
            - Mode name (e.g., "INVESTIGATIVE", "TUTORIAL")
            - Frequency (what % of videos)
            - Typical arc structure
            - Beat preferences
            - Pacing profile
            - When this mode is used (content types)
            - Example video IDs (3-5 best examples)

            2. ENFORCEABLE CONSTRAINTS
            Quantify patterns:
            - Sentence cadence: avg length, std dev, short burst frequency
            - Tease distance: avg, max
            - Question rate: rhetorical vs genuine per 100 words
            - Data density: stats per section, examples per section

            3. ANCHOR PHRASE FAMILIES
            Organize by function (not just frequency):
            - openers: (phrases that start sections)
            - turns: (phrases that signal pivots)
            - proof_frames: (phrases that introduce evidence)
            - closers: (phrases that end sections)

            For each family, list 5-10 examples.

            4. ANTI-PATTERNS
            What does this creator AVOID?
            - Phrases never used (despite being common on YouTube)
            - Structural patterns avoided (e.g., never does listicles)
            - Topics always hedged (e.g., medical advice → disclaimer)

            5. COOLDOWN RULES
            - Minimum distance between anchor reuse
            - Maximum frequency for any single anchor

            OUTPUT FORMAT (strict JSON):
            {
              "modes": [...],
              "constraints": {...},
              "anchorLibrary": {...},
              "antiPatterns": {...},
              "cooldownRules": {...}
            }

            Return ONLY valid JSON, no markdown formatting.
            """
        }
    }
}


struct NewPromptDatabase {
    private static func getA1aPrompt() -> String {
        "A1A Prompt"
    }
    
    private static func parseA1aResponse(_ text: String) {
        
    }
    
    private static func getA1bPrompt() -> String {
        "A1B Prompt"
    }
    
    private static func parseA1bResponse(_ text: String) {
        
    }
    
    private static func getA1cPrompt() -> String {
        "A1B Prompt"
    }
    
    private static func parseA1cResponse(_ text: String) {
        
    }
    
    
    
}
