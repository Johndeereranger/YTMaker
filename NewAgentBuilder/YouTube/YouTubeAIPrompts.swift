//
//  YouTubeAIPrompts.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//

struct YouTubeAIPrompts {
    func copyPatternGuideAnalysisPrompt(selectedText: String, fullScript: String) -> String {
        // Dynamically build pattern reference from enum
        let patternReference = PatternType.allCases.map { pattern in
            let examplesList = pattern.examples
                .map { "• \($0)" }
                .joined(separator: "\n")
            
            return """
            **\(pattern.rawValue)**
            \(pattern.description)
            Examples:
            \(examplesList)
            """
        }.joined(separator: "\n\n")
        
        let prompt = """
    You are an expert script analyst specializing in YouTube content structure and persuasion mechanics. Your job is to identify which pattern(s) appear in a marked section of text.

    ## AVAILABLE PATTERNS:

    \(patternReference)

    ---

    ## MARKED TEXT TO ANALYZE:

    \(selectedText)

    ---

    ## FULL SCRIPT CONTEXT:

    \(fullScript)

    ---

    ## YOUR TASK:

    1. **Identify the primary pattern(s)** in the marked text. Most text will have 1-2 dominant patterns, but some may have 3+.

    2. **Explain your reasoning**: Walk through WHY this text matches the pattern(s) you identified. Quote specific phrases that are the "tell."

    3. **Rate the match confidence**: 
       - STRONG MATCH: Text clearly fits the pattern definition
       - PARTIAL MATCH: Has elements of the pattern but not a perfect fit
       - HYBRID: Combines multiple patterns equally

    4. **If no pattern fits well**: Describe what the text is actually DOING in the story. What function does it serve? Is it a variation of an existing pattern or something entirely different?

    5. **Suggest section type**: Based on the pattern(s), what kind of section is this? (e.g., "Authority Build," "Mystery Setup," "Context Dump," "Narrative Transition")

    Format your response like this:

    **PRIMARY PATTERN(S):** [Pattern name(s)]

    **CONFIDENCE:** [Strong Match / Partial Match / Hybrid]

    **REASONING:**
    [Your explanation with specific quotes]

    **SECTION TYPE:** [What role this plays in the overall structure]

    **ALTERNATIVE INTERPRETATION:** (if applicable)
    [Any other ways to read this text]
    """
        
        return prompt
    }
}


extension YouTubeAIPrompts {
    // MARK: - Outline Section Analysis Prompts

    func getAIPromptForOutlineSectionsHuman(fullVersion: String) -> String {
        return fullVersion + "\n\n" + promptForOutlineSectionsBase() + "\n\n" + promptForHumanOutputOutlineSection()
    }

    func getAIPromptForOutlineSectionsJSON(fullVersion: String) -> String {
        return fullVersion + "\n\n" + promptForOutlineSectionsBase() + "\n\n" + promptForJSONOutputOutlineSection()
    }

    private func promptForOutlineSectionsBase() -> String {
        // Dynamically build field definitions from OutlineSection enum
        let aiFieldDefinitions = OutlineSection.FieldType.allCases
            .filter { $0.isAIField }
            .map { field in
                let examplesList = field.examples.enumerated()
                    .prefix(3)
                    .map { "   • \($0.element)" }
                    .joined(separator: "\n")
                
                let constraintsList = field.constraints
                    .map { "   • \($0)" }
                    .joined(separator: "\n")
                
                var fieldDoc = """
                \(field.displayName):
                Purpose: \(field.purpose)
                
                Examples:
                \(examplesList)
                
                Constraints:
                \(constraintsList)
                """
                
                if let badExample = field.badExample {
                    fieldDoc += "\n\nBAD Example:\n   • \(badExample)"
                }
                
                return fieldDoc
            }.joined(separator: "\n\n")
        
        return """
        ═══════════════════════════════════════════════════════════════════
        AI ANALYSIS REQUEST - REVERSE-ENGINEERED SCRIPT OUTLINE
        ═══════════════════════════════════════════════════════════════════
        
        CONTEXT:
        I've manually analyzed this video script by breaking it into sections, writing raw observations,
        identifying beliefs installed, and marking sentence-level patterns.
        
        YOUR JOB:
        For EACH section, generate ONLY the AI fields. Do NOT rewrite my fields, add/remove/reorder sections,
        or invent new sections.
        
        ───────────────────────────────────────────────────────────────────
        MY NOTES ARE PRIMARY SOURCE - READ THIS CAREFULLY
        ───────────────────────────────────────────────────────────────────
        
        My "Your Notes" field contains TWO types of information:
        
        TYPE 1 - FACTUAL OBSERVATIONS (you MUST incorporate these):
        • Visual elements: on-screen text, graphics, B-roll, sight gags, overlays
        • Cross-promotional references: mentions of other videos, content universe ties
        • Pattern markers: when I say [CROSS] or mention cross-promo, it's a FACT
        
        TYPE 2 - CONTEXTUAL OBSERVATIONS (inform your analysis):
        • My skepticism about credibility ("this feels like BS padding")
        • My interpretation of strategy ("he's oversimplifying to lower barrier")
        • My human reading of tone and manipulation
        
        CRITICAL RULES FOR MY NOTES:
        ✓ If I describe a VISUAL element → treat it as fact, include in analysis
        ✓ If I identify CROSS-PROMO → treat it as strategic fact, not optional detail
        ✓ If I call out BS → preserve and expand on my skepticism
        ✓ My general observations → use to inform tone and interpretation
        
        NOTE SIGNALS YOU MUST RESPOND TO:
        
        A) VISUAL CUE (examples: "shows him flipping the bike", "map overlay appears")
           → MUST mention in aiSummary as visual event
           → MUST include in aiMechanism (e.g., "visual proof artifact", "comic relief gag")
           → MUST include in aiInputsRecipe as categorical ingredient (e.g., "comic relief visual")
           → If transcript doesn't show it, prefix: "Visual-only: [description]"
        
        B) CROSS-PROMO (examples: "he's cross-promoting his trail camera video", "references other content")
           → MUST reflect in aiStrategicPurpose (e.g., "...while cross-promoting related content")
           → MUST reflect in aiMechanism (e.g., "content universe bridge", "channel ecosystem tie-in")
           → MUST flag in aiBSFlags if it interrupts flow or creates viewer exit risk
           → Even if transcript only says "I've previously stated...", treat as cross-promo
        
        C) NOTES vs TRANSCRIPT CONFLICT
           → Do NOT resolve disagreements between my notes and transcript
           → Add to aiBSFlags: "Notes indicate [X], transcript shows [Y]; likely visual/context gap"
        
        ───────────────────────────────────────────────────────────────────
        FIELD DEFINITIONS
        ───────────────────────────────────────────────────────────────────
        
        \(aiFieldDefinitions)
        
        ADDITIONAL FIELD REQUIREMENTS:
        
        aiSummary MUST include:
        • Any major VISUAL CUE mentioned in my notes (even if transcript can't show it)
        • Format: "Shows/displays [visual element]. [rest of summary]"
        
        aiBSFlags MUST include:
        • Any cross-promo or content universe bridge I identified
        • Visual techniques I called out as credibility inflation
        • Conflicts between my notes and what transcript shows
        
        ───────────────────────────────────────────────────────────────────
        CRITICAL RULES
        ───────────────────────────────────────────────────────────────────
        
        ✓ MY NOTES = PRIMARY SOURCE - don't treat transcript as more authoritative
        ✓ When I say "you can't see from the text but...", that's CRITICAL FACTUAL CONTEXT
        ✓ Preserve my raw judgments - if I said something is BS, don't soften it
        ✓ Don't invent sections I didn't identify or patterns I didn't mark
        ✓ Make aiInputsRecipe categorical (not literal facts from his video)
        ✓ Stay focused on making this REUSABLE for writing my own scripts
        ✓ If section is extremely short, keep outputs short - don't pad
        
        ───────────────────────────────────────────────────────────────────
        EXAMPLES - How to handle my notes correctly
        ───────────────────────────────────────────────────────────────────
        
        EXAMPLE 1 - Visual Cue:
        My Note: "He has a video of him flipping over backwards on the mountain bike"
        
        Your Response MUST include:
        • aiSummary: "Visual-only: Shows bike flip fail. [rest of summary]"
        • aiMechanism: "Self-deprecating visual gag + comic relief timing + hardship-as-credential"
        • aiInputsRecipe: "Pain framing, self-deprecating humor, comic relief visual"
        
        EXAMPLE 2 - Cross-Promo:
        My Note: "He's cross-promoting his trail camera video"
        Transcript: "I've previously stated my reservations about trail cameras..."
        
        Your Response MUST include:
        • aiStrategicPurpose: "Provide guidance while cross-promoting trail camera content universe"
        • aiMechanism: "Content universe bridge + disclaimer hedging + caveat-based authority"
        • aiBSFlags: "Cross-promo to separate video interrupts flow. Viewer exit risk."
        
        EXAMPLE 3 - My BS Detection:
        My Note: "This is 100% pointless foundational basics that everyone knows"
        
        Your Response MUST include:
        • aiBSFlags: "Foundational padding. Obvious principle presented as 'most important step'. Inflated significance relative to basic content."
        
        ═══════════════════════════════════════════════════════════════════
        """
    }

    private func promptForHumanOutputOutlineSection() -> String {
        return """
        ───────────────────────────────────────────────────────────────────
        OUTPUT FORMAT (Human-Readable)
        ───────────────────────────────────────────────────────────────────
        
        For each section, output:
        
        SECTION [number]: [original title]
        aiTitle: [reusable archetype name]
        aiSummary: [1-3 sentences, literal events only]
        aiStrategicPurpose: [function/belief installed]
        aiMechanism: [technique + technique + technique]
        aiInputsRecipe: [category + category + category]
        aiBSFlags: [credibility audit - be specific and sharp]
        aiArchetype: [stable class label for clustering]
        
        ---
        
        After all sections, add:
        
        OVERALL INSIGHTS:
        - Most common archetypes used
        - Structural patterns (which archetypes appear where)
        - Recurring mechanisms across sections
        - Where BS is concentrated
        
        ═══════════════════════════════════════════════════════════════════
        """
    }

    private func promptForJSONOutputOutlineSection() -> String {
        return """
        ───────────────────────────────────────────────────────────────────
        OUTPUT FORMAT (STRICT JSON ONLY)
        ───────────────────────────────────────────────────────────────────
        
        ✓ Output STRICT JSON only (no markdown, no preamble, no ```json```)
        ✓ Make aiInputsRecipe a string (comma-separated categories)
        ✓ Make aiBSFlags a string (bullet points if multiple)
        
        JSON Structure:
        
        {
          "sections": [
            {
              "sectionNumber": 1,
              "sourceTitle": "Historical Ramble",
              "aiTitle": "Credibility Ramble",
              "aiSummary": "Discusses food plot history, drought conditions, planting methods.",
              "aiStrategicPurpose": "Establish perceived expertise through irrelevant familiarity signals",
              "aiMechanism": "Effort-based trust + scope inflation + irrelevant detail padding",
              "aiInputsRecipe": "Historical context, constraint details, effort signals, method details",
              "aiBSFlags": "Largely irrelevant to hunt. No denominator on scope claims. Credibility padding.",
              "aiArchetype": "Credibility Ramble"
            }
          ]
        }
        
        Return JSON with this exact structure:
        - "sections" array with one object per section
        - "sectionNumber" matches the section number in the full version
        - "sourceTitle" is the exact title shown after "=== SECTION N: ..."
        - All 7 AI fields as strings (even if multi-line, keep as single string)
        - No extra fields, no nested objects beyond the structure shown
        
        ═══════════════════════════════════════════════════════════════════
        """
    }
}
