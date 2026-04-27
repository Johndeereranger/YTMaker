//
//  YTSCRIPTOutlinePrompts.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/1/26.
//


import Foundation

struct YTSCRIPTOutlinePrompts {
    
    static func generatePrompt(for style: WritingStyle, script: YTSCRIPT) -> String {
        switch style {
        case .kallaway:
            return generateKallawayPrompt(script: script)
        case .derrick:
            return generateDerrickPrompt(script: script)
        default:
            return generateKallawayPrompt(script: script)
        }
    }
    
    // MARK: - Kallaway Outline Prompt
    
    static func generateKallawayPrompt(script: YTSCRIPT) -> String {
        // Format research points
        let pointsText = script.researchPoints.enumerated().map { index, point in
            """
            ### Point \(index + 1): \(point.title)
            \(point.rawNotes)
            """
        }.joined(separator: "\n\n")
        
        // Get selected angle if exists
        let angleText: String
        if !script.manualAngle.isEmpty {
            angleText = "SELECTED ANGLE:\n\(script.manualAngle)\n\n"
        } else if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
            angleText = """
            SELECTED ANGLE:
            - Statement: \(selectedAngle.angleStatement)
            - Nuke Point: \(selectedAngle.nukePoint)
            - Hook Type: \(selectedAngle.hookType)
            - Supporting Points: \(selectedAngle.supportingPoints.joined(separator: ", "))
            
            """
        } else {
            angleText = ""
        }
        
        return """
        You are creating a YouTube video outline based on thermal drone research findings.
        
        CONTEXT:
        - Mission: \(script.objective)
        - Target Emotion: \(script.targetEmotion)
        - Audience: \(script.audienceNotes)
        - Target Duration: \(String(format: "%.1f", script.targetMinutes)) minutes
        
        \(angleText)RESEARCH POINTS:
        \(pointsText)
        
        YOUR TASK:
        Create a video outline with 5-8 sections that tells a compelling story.
        
        REQUIREMENTS:
        1. Start with Hook/Intro section
        2. Arrange middle sections using strong storytelling (consider 2-1-3-4 if applicable)
        3. End with Outro section
        4. Each section needs:
           - Clear section name
           - 3-5 key bullet points of what to cover
        5. DO NOT include word counts or time estimates (I'll set those)
        6. Merge related research points if it makes sense
        7. Use the selected angle to guide the story structure
        
        OUTPUT FORMAT:
        Return ONLY valid JSON in this exact structure:
        
        {
          "outline": [
            {
              "id": 1,
              "section_name": "Hook/Intro",
              "key_points": [
                "Context & click confirmation",
                "State common belief",
                "Contrast with contrarian take from data",
                "Show credibility (thermal drone study)",
                "Lay out plan for video"
              ]
            },
            {
              "id": 2,
              "section_name": "Section title here",
              "key_points": [
                "Bullet point 1",
                "Bullet point 2",
                "Bullet point 3"
              ]
            }
          ]
        }
        
        Generate the complete outline and return as JSON.
        """
    }
    
    // MARK: - Derrick Outline Prompt
    
    static func generateDerrickPrompt(script: YTSCRIPT) -> String {
        let pointsText = script.researchPoints.enumerated().map { index, point in
            """
            ### Point \(index + 1): \(point.title)
            \(point.rawNotes)
            """
        }.joined(separator: "\n\n")
        
        let angleText: String
        if !script.manualAngle.isEmpty {
            angleText = "SELECTED ANGLE:\n\(script.manualAngle)\n\n"
        } else if let selectedAngle = script.generatedAngles.first(where: { $0.id == script.selectedAngleId }) {
            angleText = """
            SELECTED ANGLE:
            - Statement: \(selectedAngle.angleStatement)
            - Nuke Point: \(selectedAngle.nukePoint)
            
            """
        } else {
            angleText = ""
        }
        
        return """
        You are analyzing research notes to determine whether they can support a high-integrity
        thermal drone whitetail analysis video in Byron's style, and if so, build the outline.
        
        Your job is NOT to write a script yet.
        Your job is quality control + structural guidance, not content creation.
        
        ═══════════════════════════════════════════════════════════
        CONTEXT (DO NOT USE TO FORCE PASSING)
        ═══════════════════════════════════════════════════════════
        
        Mission / Objective: \(script.objective)
        Target Emotion: \(script.targetEmotion)
        Audience Notes: \(script.audienceNotes)
        Target Duration: \(String(format: "%.1f", script.targetMinutes)) minutes
        
        IMPORTANT:
        - These fields provide INTENT, not justification.
        - Do NOT allow mission, emotion, or audience to override failed gates.
        - If gates fail, the idea fails regardless of intent.
        
        \(angleText)RESEARCH POINTS:
        \(pointsText)
        
        ═══════════════════════════════════════════════════════════
        PHASE 1: STRUCTURAL VALIDATION (MUST PASS ALL GATES)
        ═══════════════════════════════════════════════════════════
        
        Before building any outline, check these SIX GATES in order.
        If ANY gate fails, STOP and report which gate failed + why.
        
        GATE 1 — OBSERVED ANOMALY CHECK
        Question: "Is there something that happened that violates common hunting beliefs?"
        
        Required elements:
        - A specific event, pattern, or behavior that contradicts expectations
        - Clear contrast between "what hunters think" vs "what actually occurred"
        - The anomaly must be concrete and falsifiable, not just rhetorically surprising
        
        Examples of PASS:
        ✓ "Buck browsed in food plot all day" (violates nocturnal belief)
        ✓ "Mature buck didn't flee when bumped" (violates pressure sensitivity belief)
        ✓ "Cold front caused reallocation of time, not surge in movement" (violates cold front folklore)
        
        Examples of FAIL:
        ✗ "Here are 5 tips for hunting pressure" (no anomaly, just advice)
        ✗ "Bucks use thermals" (known fact, no surprise)
        ✗ "I saw a big deer" (observation without contradiction)
        ✗ "Deer acted strangely" (vague framing, not falsifiable anomaly)
        
        If NO clear anomaly exists → STOP
        Return: "GATE 1 FAILED: No observed anomaly that challenges existing beliefs"
        
        ---
        
        GATE 2 — TEMPORAL DEPTH CHECK
        Question: "Is there longitudinal context, not just a single moment?"
        
        Required elements:
        - Time depth: multiple observations over days/weeks/seasons
        - Historical baseline: "this is how it normally works" comparison
        - Pattern recognition across time, not isolated incident
        
        Examples of PASS:
        ✓ Tracking single buck September → December with pattern shifts
        ✓ Comparing 2024 season to 2025 season conditions
        ✓ "I've recorded this 200+ times across multiple bucks"
        
        Examples of FAIL:
        ✗ "I saw a buck do X once"
        ✗ Single-day observation with no context
        ✗ No baseline for comparison
        
        If NO temporal depth → STOP
        Return: "GATE 2 FAILED: Single observation without historical context or pattern recognition"
        
        ---
        
        GATE 3 — CONSTRAINT STACK CHECK
        Question: "Are there multiple simultaneous factors interacting?"
        
        Required elements:
        - Minimum 3 interacting constraints from different categories:
          - Environmental: weather, food availability, terrain
          - Biological: physiology, thermoregulation, digestion, hormones
          - Human: pressure, scent, access
          - Spatial: topography, cover, funnels
          - Temporal: time of day, season, phase
        - If constraints are listed but their interaction is unclear → STOP
        
        Examples of PASS:
        ✓ Drought + acorn failure + food plots + hunting pressure + rut timing
        ✓ Heat + winter coat + metabolism + radiant cooling + movement timing
        ✓ South wind + thermal hub + doe groups + terrain + scent dynamics
        
        Examples of FAIL:
        ✗ "Thermals matter" (single factor)
        ✗ "Food sources changed" (simple cause-effect)
        ✗ Generic multi-factor list without interaction explanation
        
        If FEWER than 3 constraints OR no clear interaction → STOP
        Return: "GATE 3 FAILED: Insufficient constraint stack. Need 3+ interacting factors from different categories"
        
        ---
        
        GATE 4 — GROUND TRUTH EVIDENCE CHECK
        Question: "Is there directly observed, repeatable data?"
        
        Required elements:
        - Specific observations from thermal drone tracking
        - Quantifiable data: distances, times, dates, counts, temperatures
        - Repeated observations (not one-time events)
        - Maps, tracks, measurements
        
        Examples of PASS:
        ✓ "Tracked this buck 200+ hours, he entered fields 2 times for 30 total minutes"
        ✓ "All 4 mature bucks stood up at 4:01pm when temp peaked at 46°"
        ✓ "308 instances recorded by drone vs 59 by trail cameras"
        
        Examples of FAIL:
        ✗ "I think bucks do this" (opinion)
        ✗ "Hunters say this happens" (hearsay)
        ✗ Speculation without observation backing it
        
        If observations rely primarily on assumption or hearsay → STOP
        Return: "GATE 4 FAILED: Insufficient ground truth evidence. Need specific drone observations with data"
        
        ---
        
        GATE 5 — INTERPRETIVE GAP CHECK
        Question: "Is there clear separation between what was seen vs what it means?"
        
        Required elements:
        - Explicit acknowledgment of uncertainty
        - "Here's what I know" vs "Here's what I think" separation
        - Multiple hypotheses considered when uncertain
        - Constraint on certainty (not overstated conclusions)
        
        Examples of PASS:
        ✓ "I can't prove this without a collar, but here's what I think..."
        ✓ "Maybe he got hit by a car, or killed by a neighbor, or he's just mobile - here's what I believe"
        ✓ "This is where human interpretation starts"
        
        Examples of FAIL:
        ✗ Presenting theories as facts
        ✗ Single explanation with no alternatives
        ✗ Overconfident conclusions from limited data
        
        If interpretation is presented as certainty OR no uncertainty acknowledged → STOP
        Return: "GATE 5 FAILED: No clear boundary between observation and interpretation"
        
        ---
        
        GATE 6 — TRANSFERABLE PRINCIPLE CHECK
        Question: "Does this reveal a lens/principle that applies beyond this one instance?"
        
        Required elements:
        - General principle that hunters can apply to their situation
        - Mental model shift, not just a tactic
        - Applicable across different properties/deer/contexts
        
        Examples of PASS:
        ✓ "Thermoregulation governs movement timing more than folklore cold fronts"
        ✓ "Invisible funnels require topo + boots, not just maps"
        ✓ "Trail cameras show 20% of activity - woods are bigger than we think"
        
        Examples of FAIL:
        ✗ "Hunt this specific tree on my property"
        ✗ "This one buck did this thing" (no broader lesson)
        ✗ Tactic without principle
        
        If takeaway only applies to this specific deer/property → STOP
        Return: "GATE 6 FAILED: No transferable principle - specific situation only"
        
        ═══════════════════════════════════════════════════════════
        PHASE 2: STORY ARC IDENTIFICATION
        (Only proceed if all gates passed)
        ═══════════════════════════════════════════════════════════
        
        Now identify which of Byron's 5 STORY ARC TYPES best fits this content:
        
        ARC TYPE 1: LINEAR MYSTERY SOLVE
        Signals: Tracking specific deer over time, "what happened to this buck?"
        Emotional Arc: Curiosity → Pattern → Disruption → Theory → Insight
        Core Question: "What happened and why?"
        
        Typical flow:
        - Hook: Introduce deer character + mystery promise
        - Context: Property/season baseline
        - Normal Patterns: Documented baseline behavior
        - The Change: Pressure, disappearance, shift
        - Investigation: Track changes chronologically
        - Theory: "Here's what I think happened"
        - Lessons: Hunting applications
        
        Examples: Buck 52, Winter, 6x5
        
        ---
        
        ARC TYPE 2: MYTH INVESTIGATION
        Signals: Testing common belief, "is this actually true?"
        Emotional Arc: Skepticism → Testing → Understanding → Nuance → Wisdom
        Core Question: "Is the conventional wisdom true?"
        
        Typical flow:
        - Hook: State the myth being tested
        - [Optional] History: Where belief originated
        - Why It Matters: Hunter pain point
        - Test Setup: How you investigated
        - Field Example 1: First data point
        - [Optional] Science: Why pattern exists
        - Field Example 2: Contrasting case
        - Truth: What data actually shows
        - Application: How to hunt based on reality
        
        Examples: Nocturnal bucks, Trail cameras, Spooked deer
        
        ---
        
        ARC TYPE 3: EDUCATIONAL FRAMEWORK
        Signals: Teaching concept/system, introducing new terminology
        Emotional Arc: Intrigue → Learning → Recognition → Application → Empowerment
        Core Question: "How does this system work?"
        
        Typical flow:
        - Hook: Tease overlooked concept
        - Why This Matters: Context
        - Define Concept: Name it, explain it
        - [Optional] Deep Dive: Component breakdown
        - Mechanism: How it works (biology/physics)
        - Field Recognition: Find it on your property
        - Case Study: Thermal data example
        - Strategy: How to position
        - Tactical Steps: Specific actions
        
        Examples: Microbiome/early season, Thermal hubs, Invisible funnels
        
        ---
        
        ARC TYPE 4: RESEARCH SUMMARY (MULTI-TOPIC)
        Signals: Multiple distinct findings, "3 things I learned"
        Emotional Arc: Curiosity → Discovery → Discovery → Discovery → Inspiration
        Core Question: "What did a body of research reveal?"
        
        Typical flow:
        - Meta Intro: Scope of research
        - Personal Context: Why you did this
        - Topic 1 Name + Deep Dive
        - Topic 2 Name + Deep Dive
        - Topic 3 Name + Deep Dive
        - Reflection: What's next
        
        Examples: 1 Year of Research
        
        ---
        
        ARC TYPE 5: EXPERIMENT DOCUMENTATION
        Signals: Testing across multiple properties, comparative study
        Emotional Arc: Intrigue → Test → Test → Test → Complexity → Wisdom
        Core Question: "What happens when we test this across contexts?"
        
        Typical flow:
        - Hook: What you're testing + why
        - Ethics/Methodology: How kept scientific
        - Study Design: Clear methodology
        - Case 1, 2, 3: Different properties + results
        - Pattern Analysis: What emerged
        - Why Differences: Individual variation
        - Nuanced Conclusion: "It depends"
        - Application: When to use insights
        
        Examples: Spooked deer pressure study
        
        ---
        
        SELECT ONE arc type and explain in 2-3 sentences why it fits.
        
        ═══════════════════════════════════════════════════════════
        PHASE 3: BUILD THE OUTLINE
        (Only proceed if arc type identified)
        ═══════════════════════════════════════════════════════════
        
        Now create 5-12 sections using TWO-TIER BULLET SYSTEM:
        
        ✓ CONTENT BULLETS = Details FROM the research notes provided
        ⚠️ RECORD BULLETS = Guidance for what Byron needs to add when recording
        
        RULES FOR CONTENT BULLETS (✓):
        - Only use when Byron explicitly provided the detail
        - Be specific: exact numbers, dates, distances, observations
        - Never invent data - if uncertain, use ⚠️ RECORD instead
        
        Examples:
        ✓ "Buck 52 is 6-7 years old, been on camera since age 2"
        ✓ "October 16th: semi-straight line, clearcut bed, scent checked 15-20 does"
        ✓ "All 4 bucks stood at 4:01pm when temp peaked at 46°F"
        
        RULES FOR GUIDANCE BULLETS (⚠️ RECORD:):
        - Use when research is thin or missing story elements
        - Be SPECIFIC about what you need - ask targeted questions
        - Frame as prompts that guide Byron's recording
        
        Examples:
        ⚠️ RECORD: Why does this buck matter? What makes him special vs others you've tracked?
        ⚠️ RECORD: Set the stakes - what question are you trying to answer?
        ⚠️ RECORD: Walk through the map - "Let's pull up a map and..."
        ⚠️ RECORD: Explain this mechanism like talking to a hunting buddy at camp
        ⚠️ RECORD: Be honest about what you DON'T know - say 'I think' not 'I know'
        
        ---
        
        SECTION REQUIREMENTS:
        
        1. First section MUST be Hook/Intro matching the arc type
        
        2. Section count: 5-12 sections (let content dictate, don't force)
        
        3. Each section needs:
           - Clear, descriptive section_name (specific, not generic)
           - 3-10 key_points mixing ✓ and ⚠️ bullets
        
        4. Include these SPECIAL SECTIONS when relevant:
        
           PATREON PITCH (if video >10 min):
           - Place after first major value (usually section 3-4)
           - Section name: "Patreon Mid-Roll"
           
           VISUAL MAPPING (when showing maps):
           - Flag in section name with [MAP]
           - Include bullets for map walkthrough
           
           THEORY/SPECULATION (when uncertain):
           - Section name: "Theory: What I Think Happened"
           - Must acknowledge uncertainty
           - List multiple hypotheses
           
           SCIENCE DEEP DIVE (biology/physics):
           - Section name: "Science Deep Dive: [Topic]"
           - Teacher intro tone
           - Component breakdown
           
           HOW WOULD YOU HUNT THIS? (tactical):
           - Usually last third of video
           - Wrong approach + why it fails
           - Right approach + conditions
        
        5. Logical flow between sections - each builds on previous
        
        6. When research is thin, use MORE ⚠️ RECORD bullets with specific guidance
        
        ═══════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════
        
        Return as valid JSON:
        
        {
          "validation_status": "PASSED" or "FAILED",
          "failed_gate": null or "GATE X: reason",
          "story_arc": {
            "type": "Linear Mystery Solve | Myth Investigation | Educational Framework | Research Summary | Experiment Documentation",
            "reasoning": "2-3 sentences why this arc fits",
            "emotional_journey": "Start → Middle → End emotions",
            "core_question": "The central question this video answers"
          },
          "outline": [
            {
              "id": 1,
              "section_name": "Hook: [Descriptive Name]",
              "key_points": [
                "✓ Content from research",
                "⚠️ RECORD: Guidance for what to add"
              ]
            }
          ]
        }
        
        If validation FAILED, return only:
        {
          "validation_status": "FAILED",
          "failed_gate": "GATE X: detailed explanation of why it failed and what's needed"
        }
        
        ═══════════════════════════════════════════════════════════
        CRITICAL FINAL REMINDERS
        ═══════════════════════════════════════════════════════════
        
        - DO NOT invent structure if content doesn't support it
        - DO NOT force into arc type if it doesn't fit
        - DO NOT fill gaps creatively - use ⚠️ RECORD bullets instead
        - DO separate observation from interpretation
        - DO acknowledge when data is thin
        - DO refuse politely if content isn't ready
        
        Your job is quality control + structural guidance, not content creation.
        """
    }
}
