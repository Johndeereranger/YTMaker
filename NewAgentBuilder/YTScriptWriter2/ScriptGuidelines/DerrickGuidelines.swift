//
//  DerrickGuidelines.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

extension ScriptGuidelinesDatabase {
    static var derrickGuidelines: [ScriptGuideline] = [
        
        ScriptGuideline(
            category: .derrick,
            title: "Ownership Density",
            summary: "Your video must feel uncopyable because it's built on YOUR specific footage, property, season, and failures.",
            explanation: """
            Ownership Density measures whether another creator could plausibly make your exact video without your unique assets. This is the single strongest predictor of performance—videos with low ownership consistently cap under 100K views, while high-ownership videos floor at 100K+.
            
            High ownership means:
            - Only YOU have this footage (your thermal drone, your property, your bucks)
            - Time investment is visible and quantified ("200 hours tracking," "7 consecutive nights," "entire season")
            - Specific property/buck/test is named and referenced throughout
            - Personal failures and wrong predictions are admitted ("I thought he'd bed here... I was wrong")
            
            Low ownership means:
            - Generic advice anyone could give
            - Data without context ("studies show..." without YOUR study)
            - Concepts explained without YOUR evidence
            - No visible cost or sacrifice
            
            BAD: "Mature bucks become nocturnal due to hunting pressure. Research shows they shift movement patterns to avoid hunters. Here are 5 tips to adjust your strategy."
            
            This script has ZERO ownership. Any hunting educator could write this. No specific buck, property, footage, or personal investment. Result: viewer thinks "I can get this elsewhere" and retention collapses.
            
            GOOD: "I tracked a buck I call Winter for 200 hours last season. He appeared on camera 47 times—but only twice in daylight. I thought he'd gone nocturnal. Then on November 8th, a cold front hit, and my thermal drone caught him at 2:00 PM, moving aggressively through terrain he'd avoided for weeks. Here's what changed."
            
            This script has HIGH ownership. Only this creator has Winter's footage, this property's conditions, this specific tracking investment. No one else can replicate this video. Result: viewer understands this is exclusive content worth watching fully.
            
            The ownership test has 4 components (must pass 3 of 4):
            1. Could another creator make this video without your footage? (NO = high ownership)
            2. Is time/effort investment visible and quantified? ("200 hours," "entire season," "5 consecutive cold fronts")
            3. Is a specific property, buck, or test named and referenced? (Winter, Thermal Hub Ridge, 7-night corn study)
            4. Are personal failures, wrong predictions, or vulnerabilities shown? ("I assumed X... but Y happened")
            
            Videos that fail ownership:
            - "How Deer See Scrapes: Unveiling Thermal Insights" (17K views) - Generic concept, no named buck, replicable by anyone
            - "One Rut Mistake Costs 50% More Bucks (Data Proves It)" (46K views) - Generic tips, no specific hunter's story
            - "Best Rut Days: 500,000 Deer Studied" (59K views) - Data without personal investment visible
            
            Videos that pass ownership:
            - "I Tracked a Mature Buck for a Full Day" (421K views) - Named buck, specific day, unreplicable footage
            - "1 Year of Thermal Whitetail Research Taught Me" (513K views) - Year-long investment, specific methodology
            - "I Spooked 100+ Deer on Purpose" (186K views) - Specific test only this creator ran
            
            Ownership isn't about production quality or equipment—it's about whether the story could only come from YOU.
            """,
            checkPrompt: """
            Analyze this hunting education script for Ownership Density:

            {{SCRIPT}}

            Ownership Density measures whether another creator could make this exact video without the creator's unique footage, property, or investment. High ownership = uncopyable content. Low ownership = generic advice anyone could give.

            Rate this script 1-10 on ownership (1 = completely generic, 10 = absolutely unique to this creator), then provide:

            1. FOOTAGE DEPENDENCY: What specific footage/evidence does this script require that only this creator would have?
            2. TIME INVESTMENT SIGNALS: Where does the script show visible effort? Quote any mentions of hours, seasons, days, repeated attempts.
            3. NAMED SPECIFICS: List any named bucks, specific properties, or unique tests mentioned. If none, state "No named elements."
            4. VULNERABILITY MOMENTS: Quote any lines where the creator admits failure, wrong predictions, or confusion.
            5. REPLICABILITY TEST: Could another hunting educator with thermal drone access make this same video using different footage? If YES, ownership is too low.
            6. COMPARISON: Does this script feel more like "I discovered something on MY property" or "Here's what research shows"?

            Provide specific line quotes to support your rating. If ownership score is below 6, explain what's missing and why this would likely cap under 100K views.
            """,
            fixPrompt: """
            Rewrite this script to maximize Ownership Density:

            {{SCRIPT}}

            Your task: Transform this script so that ONLY this creator could make this video. Follow these rules strictly:

            1. NAME THE PROTAGONIST: If there's a buck/deer, give it a specific name (Winter, Phantom, Ghost, Ridge Runner) and reference it throughout. Include physical traits (limping front foot, split G2, massive 8-point).

            2. QUANTIFY TIME INVESTMENT: Add specific numbers. Replace vague references with:
               - "I tracked him for 200 hours over 6 months"
               - "Seven consecutive nights of thermal flights"
               - "This was night 4 of the test"
               - "I've documented this buck 63 times across two seasons"

            3. NAME THE PROPERTY FEATURES: Replace "the ridge" with "Thermal Hub Ridge." Replace "a bedding area" with "the north drainage convergence." Give landmarks names the creator would actually use.

            4. ADD FAILED PREDICTIONS: Insert 2-3 moments where the creator was wrong:
               - "I assumed he'd bed on the north slope. He didn't. I lost him for 20 minutes..."
               - "I thought this would prove X. The footage showed Y instead."

            5. MAKE IT UNREPLICABLE: Ensure at least 3 elements that require THIS creator's unique situation (their property layout, their specific buck, their multi-week investment, their particular test setup).

            Output the rewritten script sentence by sentence, maintaining the original structure but injecting ownership throughout. Mark each ownership injection with [OWNERSHIP: ...] tags so they're visible.
            """,
            suggestionsPrompt: """
            Review this script for Ownership Density improvements:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to increase ownership (making the video feel uncopyable). For each suggestion:

            FORMAT:
            CURRENT: [Quote the generic/low-ownership line]
            IMPROVED: [Show the high-ownership rewrite]
            WHY: [Explain how this increases ownership]

            Focus on:
            1. Naming unnamed bucks, properties, or terrain features
            2. Adding specific time investments where currently vague
            3. Inserting personal failures or wrong predictions
            4. Replacing "research shows" with "when I tested this on my property"
            5. Adding details that only this creator would know (specific bedding locations, trail camera timestamps, weather on specific dates)

            Prioritize changes that would make another creator think "I literally cannot make this video without his footage/property/investment."
            """
        ),

        ScriptGuideline(
            category: .derrick,
            title: "Event Language (Not Topic)",
            summary: "Frame content as a specific event that happened, not a general truth to teach.",
            explanation: """
            Event Language vs Topic Language is the fundamental framing choice that determines whether your video feels like a documentary or a lecture. Topic Language triggers "classroom mode" where viewers want efficiency and leave once satisfied. Event Language triggers "story mode" where viewers want resolution and stay engaged.
            
            Topic Language sounds like:
            - "How deer see scrapes"
            - "The science behind nocturnal behavior"
            - "Why bucks avoid corn"
            - "Understanding thermal hubs"
            
            Event Language sounds like:
            - "I watched a buck hesitate at the scrape every night for a week"
            - "I tracked a buck through a cold front to see if he'd go nocturnal"
            - "Seven nights of corn... and the biggest buck never touched it"
            - "I followed Winter to his bedding area and found this"
            
            The critical distinction: Topics describe WHAT IS TRUE. Events describe WHAT HAPPENED.
            
            BAD TITLE: "How Deer See Scrapes: Unveiling Thermal Drone Insights" (17K views)
            
            This is pure Topic Language. "How deer see" is a general truth. "Unveiling insights" is academic. Result: viewer brain says "this is educational content" and expects a lesson. Retention collapses because the video feels like replaceable information.
            
            GOOD TITLE: "I Tracked a Mature Buck for a Full Day" (421K views)
            
            This is pure Event Language. "I tracked" is an action that happened. "Full day" shows investment. "Mature buck" is the character. Result: viewer brain says "something happened and I want to see it" and stays engaged because this is a unique story.
            
            Event Language requires:
            
            1. ACTION VERBS in title and opening: tracked, tested, watched, followed, spooked, discovered, caught, waited (NOT: discussing, explaining, exploring, revealing, unveiling)
            
            2. FIRST 15 SECONDS = CONCRETE CONTRADICTION: Not "Today we'll discuss why bucks avoid corn." But: "I put corn out for seven straight nights. The biggest buck on the property walked within 30 yards every evening. He never touched it."
            
            3. "I" PERSPECTIVE DOMINATES: The creator is present in the action. Not "Bucks do this because..." but "I watched this buck do this, then this happened..."
            
            4. REMOVE "YOU/YOUR" TEST: If you delete all instances of "you/your" and the script still flows naturally, it's Event Language. If it falls apart, it was lecture-mode Topic Language.
            
            Examples contrasted:
            
            TOPIC (kills retention): "Mature bucks often become more cautious around bait sites due to increased hunting pressure. Understanding their hesitation patterns can help you position stands more effectively. Let's explore the science behind bait avoidance."
            
            EVENT (drives retention): "November 4th, 6:47 PM. The 8-point I've been tracking approaches my corn pile. He stops at 32 yards. Stares. Four minutes—he doesn't move closer. I've got him on thermal for the next six nights. Same pattern. Always stops in this zone. Never commits. Here's what the footage revealed."
            
            Why this matters psychologically:
            
            Topics = Information Transfer Mode
            - Viewer wants to extract knowledge efficiently
            - Once core concept is grasped, watching becomes optional
            - Comments are polite: "Good info, thanks"
            - No rewatch value
            
            Events = Story Following Mode  
            - Viewer wants to see how it resolves
            - Must watch to find out what happened
            - Comments are engaged: "Did you ever get him?" "I saw this on my property too"
            - High rewatch value (especially specific moments)
            
            Your data proves this:
            - Event Language videos: 83K-513K views (consistent performance)
            - Topic Language videos: 17K-59K views (consistent underperformance)
            
            The shift is often just one word in the title:
            - "Why Bucks Ghost Corn" → "I Know Why That Buck Ghosted My Corn"
            - "Understanding Nocturnal Behavior" → "I Tracked a 'Nocturnal' Buck... He Wasn't"
            - "Rut Hunting Mistakes" → "This Rut Mistake Cost Me Thunder"
            """,
            checkPrompt: """
            Analyze this script for Event Language vs Topic Language:

            {{SCRIPT}}

            Event Language = framing as "something that happened" (story mode, high retention)
            Topic Language = framing as "something that is true" (classroom mode, low retention)

            Rate this script 1-10 on Event Language (1 = pure lecture, 10 = pure event narrative), then analyze:

            1. TITLE/OPENING FRAMING: Quote the first 2-3 sentences. Do they describe an event that happened or a topic to explore?

            2. VERB ANALYSIS: List the main verbs in the first minute. Are they action verbs (tracked, watched, tested, followed) or teaching verbs (discussing, explaining, exploring, understanding)?

            3. PERSPECTIVE TEST: What percentage of sentences use "I" perspective vs "you/your" perspective? High "you/your" = Topic Language lecture mode.

            4. REMOVE "YOU" TEST: If you deleted every instance of "you/your," would the script still flow naturally? If NO, it's lecture-mode Topic Language.

            5. CONCRETE VS ABSTRACT: Quote 3 examples showing whether script uses:
               - Concrete events: "November 4th, the buck stopped at 32 yards"
               - Abstract concepts: "Bucks often hesitate due to pressure"

            6. CLASSROOM SIGNALS: Flag any phrases that trigger academic mode:
               - "Let's explore..."
               - "Understanding how..."
               - "The science behind..."
               - "Here's why this matters..."
               - "Today we'll discuss..."

            Provide your rating and specific line quotes. If score is below 6, explain how Topic Language is killing retention.
            """,
            fixPrompt: """
            Rewrite this script in pure Event Language:

            {{SCRIPT}}

            Your task: Transform every Topic Language phrase into Event Language. Follow these rules:

            1. START WITH CONCRETE CONTRADICTION (first 15 seconds):
               Replace: "Today we'll discuss why bucks avoid corn"
               With: "Seven nights. Corn pile. Biggest buck walked 30 yards away every evening. Never touched it. Here's the thermal footage."

            2. CONVERT ALL TEACHING VERBS TO ACTION VERBS:
               Replace: "I'm going to explain/discuss/explore"
               With: "I tracked/watched/tested/followed/discovered"

            3. REMOVE "YOU/YOUR" CLASSROOM LANGUAGE:
               Replace: "This will help you understand how deer..."
               With: "When I watched this buck, he..."
               Replace: "You should position your stand..."
               With: "After seeing where he stopped, I moved my stand..."

            4. REPLACE ABSTRACTS WITH SPECIFIC EVENTS:
               Replace: "Bucks often become cautious around bait"
               With: "The 8-point stopped at 32 yards, stared at the corn for 4 minutes, then left"

            5. ADD "I" PERSPECTIVE TO EVERY OBSERVATION:
               Replace: "Research shows bucks move more on cold fronts"
               With: "I tracked Winter on November 8th when temps dropped. He moved 1,200 yards—3X his normal pattern."

            Output the rewritten script maintaining all key information but framed as events that happened to this specific creator on their specific property. Mark conversions with [EVENT: ...] tags.
            """,
            suggestionsPrompt: """
            Identify Topic Language weaknesses in this script:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to convert Topic Language into Event Language. For each:

            FORMAT:
            CURRENT: [Quote the topic/teaching language]
            IMPROVED: [Show the event language version]  
            WHY: [Explain how this shifts from classroom to story mode]

            Focus on:
            1. Title/opening lines that sound academic or educational
            2. "You/your" language that creates lecture mode
            3. Abstract concepts that should be specific events
            4. Teaching verbs that should be action verbs
            5. Generic statements that should be "I watched this buck do this"

            Prioritize changes in the first 2 minutes—that's where Event Language matters most for retention.
            """
        ),

        ScriptGuideline(
            category: .derrick,
            title: "Evidence Before Explanation",
            summary: "Show weird behavior first for 2-3 minutes, then interpret—never start with 'Here's what I found.'",
            explanation: """
            Evidence Before Explanation is the retention engine. When you explain BEFORE showing evidence, the viewer's brain closes the cognitive loop and watching becomes optional. When you show evidence FIRST, the viewer's brain forms hypotheses and the eventual explanation feels like a reward.
            
            This is not about withholding information—it's about the ORDER of information delivery.
            
            BAD STRUCTURE (Explanation First):
            "Mature bucks create a hesitation zone 25-50 yards from bait because they're evaluating risk. Here's the footage that proves it..."
            
            Brain response: "Okay, I understand the concept. Do I need to see the footage? Probably not." → Viewer leaves or skips.
            
            GOOD STRUCTURE (Evidence First):
            "November 4th. The buck approaches the corn pile. Thirty-two yards out—he stops. Stares. Four minutes. Doesn't move closer. November 5th. Same buck. Stops at 28 yards. November 6th. Thirty-five yards. Every night, he stops in this zone. Never commits. What's happening here?"
            
            Brain response: "That's weird. Why is he doing that? I need to know." → Viewer stays engaged, THEN gets rewarded with explanation.
            
            The Evidence-First structure requires:
            
            1. FIRST 2-3 MINUTES = BEHAVIOR OBSERVATION
               - Thermal footage of unexpected deer behavior
               - Trail camera sequences showing pattern
               - Tracking data revealing contradiction
               - NO interpretation yet—just "this happened, then this, then this"
            
            2. CREATE VIEWER CONFUSION → CURIOSITY → REVELATION
               - Confusion: "Wait, why would he do that?"
               - Curiosity: "Is this a pattern or fluke?"
               - Revelation: "Here's what I think is happening..." (minute 3-4)
            
            3. PATTERN PROOF REQUIREMENT
               - Single observation = anecdote ("I saw a buck avoid corn once")
               - Two contrasting observations = pattern ("Warm day: avoided corn. Cold day: still avoided corn. Same behavior, different conditions.")
               - Pattern must be shown BEFORE explained
            
            4. NEVER START WITH:
               - "Here's what I found..."
               - "Three reasons this happens..."
               - "The science shows..."
               - "Research proves..."
               These kill retention by front-loading the conclusion.
            
            Your data proves this principle:
            
            FAILED (Explanation First):
            - "One Rut Mistake Costs You 50% More Bucks" (46K) - Listed mistakes immediately, explained before showing
            - "How Deer See Scrapes" (17K) - Started with UV science concept before footage
            
            SUCCEEDED (Evidence First):
            - "I Tracked a Mature Buck for a Full Day" (421K) - 8+ minutes of tracking footage before interpretation
            - "Thermal Drone Reveals Why Bucks Ghost Your Corn" (474K) - Showed hesitation zone pattern first, explained minute 3-4
            
            The psychological mechanism:
            
            When explanation comes first:
            - Working memory stores the answer
            - Evidence becomes "proof of what I was just told"
            - No surprise, no discovery feeling
            - Retention drops because outcome is known
            
            When evidence comes first:
            - Working memory forms prediction ("Maybe he's smelling something?")
            - Evidence either confirms or contradicts prediction
            - Creates micro-surprises throughout
            - Explanation resolves tension (reward)
            - Retention stays high because brain is actively processing
            
            Implementation example:
            
            BAD OPENING (Explanation First):
            "Cold fronts don't make deer move more—they reallocate movement timing from night to day. I tracked several bucks to prove this. Let me show you the data..."
            
            Viewer brain: "Got it. Movement reallocation. I understand. Do I need to watch the rest? Eh."
            
            GOOD OPENING (Evidence First):
            "November 8th, 42 degrees, 15mph north wind. I've been tracking this buck for weeks. Warm days: he beds all day, moves at night. Today's different. 6:47 AM—he's up. He's moving. This is NOT normal. For the next 6 hours, my thermal drone follows him. Watch this..."
            
            Viewer brain: "Wait, what changed? Why is he moving now? I need to see what happens."
            
            The contrast example requirement:
            
            Evidence-First must include at least TWO contrasting observations:
            
            Pattern Type 1 - Same deer, different conditions:
            "Warm evening (68°F): Buck beds at 4 PM, doesn't move until dark.
            Cold evening (38°F): Buck beds at 4 PM, up at 6 PM, active until dark.
            Same buck. Same bedding time. Temperature changed behavior."
            
            Pattern Type 2 - Different deer, same behavior:
            "Buck #1: Stops at 28 yards from corn.
            Buck #2: Stops at 34 yards from corn.
            Buck #3: Stops at 41 yards from corn.
            Five mature bucks—all stop in 25-50 yard zone. None approach directly."
            
            Why contrasts matter: Single example could be coincidence. Contrasting examples prove it's a repeatable pattern worth explaining.
            
            Common AI failure mode:
            AI naturally wants to explain efficiently. It will write: "Based on my research, here's what happens..." This is explanation-first and kills retention. You must force evidence-first structure.
            """,
            checkPrompt: """
            Analyze this script for Evidence-First structure:

            {{SCRIPT}}

            Evidence-First = show weird behavior for 2-3 minutes before interpreting
            Explanation-First = tell viewer the conclusion, then show proof (kills retention)

            Rate this script 1-10 on Evidence-First (1 = explains immediately, 10 = shows extensively before interpreting), then analyze:

            1. OPENING ANALYSIS: Quote the first 3-4 sentences. Do they:
               - Show specific behavior/footage? (Good)
               - Explain what was discovered? (Bad)
               - Start with "Here's what I found..." or similar? (Very bad)

            2. TIME TO INTERPRETATION: How many minutes (estimate by word count) before the script explains WHY the behavior is happening? Evidence-first should be 2-3+ minutes.

            3. PATTERN PROOF: Does the script show:
               - Single observation only? (Weak—could be fluke)
               - Two contrasting observations? (Good—shows pattern)
               - Example: Same deer/different conditions OR different deer/same behavior

            4. CONCLUSION FRONT-LOADING: Flag any lines in the first 2 minutes that reveal the conclusion:
               - "The reason is..."
               - "This happens because..."
               - "Research shows..."
               - "Three factors explain this..."

            5. CURIOSITY MAINTENANCE: Does the opening create viewer questions that demand answers? Or does it answer questions before creating them?

            6. FOOTAGE/EVIDENCE DENSITY: What percentage of the first 3 minutes is:
               - Observable behavior descriptions (thermal footage, trail cam, tracking data)
               - Explanations and interpretations

            Provide your rating and specific quotes. If score is below 6, explain where explanation came too early and how it kills retention.
            """,
            fixPrompt: """
            Rewrite this script to enforce Evidence-First structure:

            {{SCRIPT}}

            Your task: Restructure so weird behavior is shown for 2-3 minutes BEFORE any interpretation. Follow these rules:

            1. OPEN WITH SPECIFIC OBSERVATION (not conclusion):
               - Date, time, conditions
               - What deer did (concrete behavior)
               - What was unexpected about it
               - NO explanation why yet

            2. BUILD PATTERN WITH CONTRASTS:
               Before ANY interpretation, show at least 2 observations:
               - Same deer, different conditions (warm day vs cold day)
               - OR different deer, same behavior (3+ bucks stopping at same zone)

            3. DELAY ALL "BECAUSE" STATEMENTS:
               Move these to minute 3-4 minimum:
               - "This happens because..."
               - "The reason is..."
               - "What I discovered was..."

            4. CREATE QUESTIONS BEFORE ANSWERS:
               - "Why does he stop here every time?"
               - "What changed on the cold day?"
               - "Is this just him, or a pattern?"
               Then answer them later.

            5. REMOVE PREMATURE TEACHING:
               Delete from first 2 minutes:
               - "Research shows..."
               - "Studies indicate..."
               - "The science behind..."
               Move these to after evidence is shown.

            Output the rewritten script with clear markers:
            [EVIDENCE: ...] for observation sections
            [INTERPRETATION: ...] for explanation sections
            
            Ensure interpretation comes AFTER sufficient evidence builds curiosity.
            """,
            suggestionsPrompt: """
            Identify Evidence-First violations in this script:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to delay explanation and prioritize evidence. For each:

            FORMAT:
            CURRENT: [Quote the premature explanation]
            IMPROVED: [Show evidence-first version]
            WHY: [Explain how delaying interpretation increases retention]

            Focus on:
            1. Opening lines that explain before showing
            2. "Here's what I found" statements in first 2 minutes
            3. Missing contrast examples (needs 2nd observation to prove pattern)
            4. Conclusions stated before evidence builds curiosity
            5. Teaching language ("because," "research shows") used too early

            Prioritize the first 3 minutes—that's where evidence-first structure matters most for retention.
            """
        ),

        ScriptGuideline(
            category: .derrick,
            title: "Sustained Uncertainty",
            summary: "Show your genuine discovery process including failures—not fake suspense but real 'I didn't know yet.'",
            explanation: """
            Sustained Uncertainty is about letting viewers experience your thinking process, including moments where you were wrong, confused, or still figuring things out. This is NOT about withholding information for drama—it's about showing HONEST confusion before arriving at honest conclusions.
            
            The psychological principle: Viewers trust discovery more than they trust teaching. When you show vulnerability and wrong predictions, you signal "this is real investigation" not "rehearsed lesson."
            
            Certainty Kills Engagement:
            - Over-confident narrator voice
            - No admitted failures
            - Every prediction was correct
            - Conclusions stated as absolute truth
            - No room for viewer interpretation
            
            Result: Viewer thinks "He's just teaching what he already knew" → passive consumption → low engagement → no comments/discussion
            
            Uncertainty Creates Engagement:
            - Admitting when predictions failed
            - Showing genuine confusion moments
            - Acknowledging gaps in understanding
            - Conclusions stated as "best current theory"
            - Inviting viewer theories
            
            Result: Viewer thinks "He's figuring this out in real-time" → active participation → high engagement → comments/theories/discussion
            
            The Implementation: "I thought X... but Y happened" (2-3 times per video)
            
            Example 1 - Failed Bedding Prediction:
            "I was betting he'd bed on the north slope. He always beds on the north slope when it's warm—I've documented it 14 times. So I flew the thermal ahead to the north slope... and he's not there. I lost him. For the next 20 minutes, I'm searching... finally, there he is—south slope, completely opposite of his pattern. What changed? I'm still not 100% sure, but here's my best guess..."
            
            Why this works:
            - Shows specific wrong prediction ("north slope")
            - Admits confusion ("I lost him")
            - Quantifies previous pattern ("14 times") making the violation surprising
            - Ends with provisional reasoning ("best guess" not "the answer")
            
            Example 2 - Unexpected Behavior:
            "I assumed he was done for the day and wouldn't be moving until evening. On the contrary, Winter decided to take a lightning-fast catnap—10 minutes—then busted absolute tail south. I'm not sure why he bedded here for only 10 minutes. Could have been resting his foot, catching his breath, or maybe he just didn't like the location. But this is one of the very few times I've observed a buck bed mid-morning movement and then get back up."
            
            Why this works:
            - States assumption ("assumed he was done")
            - Shows subverted expectation ("on the contrary")
            - Admits uncertainty ("not sure why")
            - Offers multiple theories (not one certain answer)
            - Provides context for why it's unusual
            
            The Four Techniques:
            
            1. STATE HYPOTHESIS FIRST, THEN SHOW REALITY
            "I expected X... but what actually happened was Y"
            
            Example: "I was certain bumping deer on an E-bike would educate them for weeks. That's what every article says. So I tracked the same deer before and after being spooked. Within 24 hours—normal patterns. Within 48 hours—couldn't tell anything happened. Either I'm wrong about education, or E-bikes register as vehicles not humans. I'm still figuring it out."
            
            2. ADMIT CONFUSION BEFORE REVEALING ANSWER
            "For the first three days, nothing made sense... then I noticed..."
            
            Example: "Phantom beds in a different location every single day. Day 1: northwest ridge. Day 2: southeast drainage. Day 3: northeast clearcut edge. I couldn't find a pattern. Then on day 4, I realized I was tracking the wrong variable. I was tracking bedding location. I should have been tracking wind direction. Every bed gave him downwind access to the same 5-acre oak flat. The location changed—the advantage didn't."
            
            3. SHOW YOUR FAILURES
            "This didn't work... this didn't work either... finally this worked"
            
            Example: "I tried hunting this setup on a south wind—bumped deer on entry, saw nothing. Next sit, west wind—he winded me at 60 yards. Third attempt, north wind—clean entry, three bucks passed within 30 yards. The terrain didn't just need 'good wind.' It required SPECIFIC wind."
            
            4. QUANTIFY YOUR UNCERTAINTY  
            "I've seen this pattern 14 out of 17 times. The 3 exceptions—I don't have an explanation for yet."
            
            Example: "In 47 tracking sessions, mature bucks stood up within 5-10 minutes of peak temperature 43 times. Four times they didn't. Three of those four, they had a doe bedded nearby—that makes sense. But one time, warm day, no doe, no pressure—he stayed bedded until dark. I still don't know why."
            
            Why This Matters (Your Data):
            
            Videos with high uncertainty/vulnerability:
            - "I Tracked a Mature Buck for a Full Day" (421K) - Multiple "I assumed... but" moments
            - "I Spooked 100+ Deer on Purpose" (186K) - Admitting ethical concerns and unknowns
            - "1 Year of Thermal Research" (513K) - "I'm often asked what I'm doing and why"
            
            Videos with low uncertainty (over-confident):
            - "One Rut Mistake Costs 50% More Bucks" (46K) - Definitive claims, no vulnerability
            - "Best Rut Days: 500,000 Deer Studied with 70% Accuracy" (59K) - Statistical authority, no failures shown
            
            The distinction: High-performing videos show the JOURNEY to knowledge. Low-performing videos present FINISHED knowledge.
            
            Common Mistakes:
            
            BAD Uncertainty (feels fake):
            "You won't BELIEVE what happened next..." (clickbait suspense)
            "Stay tuned to find out..." (withholding for drama)
            "The answer will SHOCK you..." (fake hype)
            
            GOOD Uncertainty (feels real):
            "I thought he'd do X... he did Y instead. Here's why I think my prediction was wrong..."
            "I'm still not 100% sure, but the evidence points to..."
            "This contradicted everything I expected..."
            
            Balance: You still need to provide value and conclusions. Uncertainty doesn't mean leaving viewers with nothing—it means showing HOW you arrived at conclusions, including the wrong turns.
            
            The Ending Uncertainty:
            Even after explaining your findings, end with:
            - What you're still testing
            - What questions remain
            - What you'll track next
            - Invitation for viewer theories
            
            Example: "So that's what 200 hours of tracking Winter taught me about morning vs evening displacement. But here's what I still don't understand: why did he violate his pattern on November 3rd? What changed that day? If you've seen this on your property, drop your theory in the comments."
            """,
            checkPrompt: """
            Analyze this script for Sustained Uncertainty:

            {{SCRIPT}}

            Sustained Uncertainty = showing your genuine discovery process including wrong predictions, confusion, and provisional conclusions (builds trust and engagement)

            Over-Confidence = teaching from position of complete certainty with no admitted failures (feels rehearsed, kills discussion)

            Rate this script 1-10 on Sustained Uncertainty (1 = overconfident teaching, 10 = transparent discovery process), then analyze:

            1. FAILED PREDICTION COUNT: How many times does the script show "I thought X... but Y happened"? Count specific instances and quote them.
               - 0 times = Over-confident (score 1-3)
               - 1 time = Minimal vulnerability (score 4-5)
               - 2-3 times = Good uncertainty (score 6-8)
               - 4+ times = Excellent transparency (score 9-10)

            2. CONFUSION MOMENTS: Quote any lines where the creator admits:
               - "I couldn't figure out..."
               - "I'm not sure why..."
               - "I lost him..."
               - "This didn't make sense..."
               If none exist, this is a major weakness.

            3. PROVISIONAL LANGUAGE: Does the script use:
               - Certain language: "This IS because..." "The reason IS..." "This proves..."
               - Provisional language: "My best guess..." "I think..." "The only explanation that fits..." "I'm still figuring out..."
               Quote examples of each.

            4. FAILURE VISIBILITY: Are any failed attempts, wrong strategies, or unsuccessful sits mentioned? Quote specific failures shown.

            5. QUANTIFIED UNCERTAINTY: Does the script quantify confidence?
               Example: "I've seen this 14/17 times. The 3 exceptions—I don't know yet."
               If so, quote. If not, note absence.

            6. INVITATION FOR INPUT: Does the ending invite viewer theories or acknowledge remaining questions? Or does it close with definitive conclusions?

            Provide your rating and specific quotes. If score is below 6, explain how over-confidence is preventing engagement and trust-building.
            """,
            fixPrompt: """
            Rewrite this script to inject Sustained Uncertainty:

            {{SCRIPT}}

            Your task: Add genuine vulnerability and discovery process. Follow these rules:

            1. INSERT FAILED PREDICTIONS (2-3 minimum):
               Add "I thought X... but Y happened" moments:
               - Wrong bedding location prediction
               - Unexpected behavior that violated pattern
               - Strategy that didn't work as planned
               Be specific about what you got wrong and what actually happened.

            2. ADD CONFUSION MOMENTS:
               Before revealing insights, show confusion:
               - "For the first three sits, I couldn't figure out..."
               - "This didn't match anything I'd seen before..."
               - "I lost him for 20 minutes..."

            3. CONVERT CERTAINTY TO PROVISIONAL LANGUAGE:
               Replace: "This IS because..." 
               With: "My best guess is..." or "The only explanation that fits..."
               Replace: "The data proves..."
               With: "The evidence suggests..." or "What I'm seeing is..."

            4. SHOW FAILED APPROACHES:
               Add at least one failed strategy:
               - "First I tried [approach]. That didn't work because..."
               - "I assumed [strategy] would work. It didn't. Here's what I learned..."

            5. QUANTIFY REMAINING UNCERTAINTY:
               End sections with:
               - "I've observed this pattern X out of Y times. The exceptions—I'm still working on."
               - "This explains most of what I saw, but not [specific case]."

            Output the rewritten script with [UNCERTAINTY: ...] tags marking each vulnerability injection. Maintain all core insights but frame them as discoveries, not lectures.
            """,
            suggestionsPrompt: """
            Identify over-confidence weaknesses in this script:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to add Sustained Uncertainty. For each:

            FORMAT:
            CURRENT: [Quote the over-confident/certain statement]
            IMPROVED: [Show vulnerable/uncertain version]
            WHY: [Explain how uncertainty builds trust and engagement]

            Focus on:
            1. Definitive statements that should be provisional ("This IS because" → "I think this is because")
            2. Missing failed predictions (where could "I thought X but Y" be added?)
            3. Explanations given without showing prior confusion
            4. Endings that close too definitively (should invite theories)
            5. Perfect predictions that feel rehearsed (should show some misses)

            Prioritize changes that make the creator feel like a real investigator, not a perfect teacher.
            """
        ),

        ScriptGuideline(
            category: .derrick,
            title: "Single Spine (No List Brain)",
            summary: "Build around ONE central behavioral mystery that repeats and escalates—not multiple tips or reasons.",
            explanation: """
            Single Spine means your video has ONE central behavioral phenomenon that appears multiple times, creating escalation and memory. List Brain means your video branches into multiple tips, reasons, or concepts, creating scatter and forgettability.
            
            Single Spine = Focused Investigation
            - One behavioral mystery: hesitation zone, shadow pattern, thermal switch, orbiting behavior
            - Same phenomenon observed 3+ times throughout video
            - Each observation adds new detail or context
            - Escalates viewer understanding gradually
            - Creates strong memory anchor
            
            List Brain = Scattered Teaching
            - Multiple separate concepts: "5 mistakes," "3 reasons," "7 tips"
            - Each point is independent
            - No escalation between points
            - Invites skipping ("I'll just watch #3")
            - Creates weak memory (which tip was which?)
            
            Why Single Spine Wins:
            
            1. MEMORY: Viewers remember "the hesitation zone video" not "one of the 5 tips was about..."
            
            2. ESCALATION: Each appearance of the spine behavior builds on the last, creating narrative momentum
            
            3. REWATCH VALUE: Viewers return to see specific moments of the spine behavior
            
            4. NO PADDING: Can't fake depth—if spine is thin, video feels thin
            
            5. PREVENTS REPETITION: AI doesn't restate the same concept in different words across list items
            
            Your Data Proves This:
            
            SINGLE SPINE (performed well):
            - "Thermal Drone Reveals Why Bucks Ghost Your Corn" (474K)
              * Spine: Hesitation zone at 25-50 yards
              * Appears: Does orbiting, buck stopping, multiple nights, pattern confirmed
              * Result: "The hesitation zone video" = memorable
            
            - "I Tracked a Mature Buck for a Full Day" (421K)
              * Spine: Winter's movement pattern through thermal hub
              * Appears: Morning departure, midday catnap, evening return, multiple contrasts
              * Result: "The Winter tracking video" = memorable
            
            LIST BRAIN (performed poorly):
            - "One Rut Mistake Costs You 50% More Bucks" (46K)
              * Structure: 5 separate mistakes listed
              * No single spine—scattered concepts
              * Result: Forgettable, feels like generic advice
            
            - "How Deer See Scrapes: Unveiling Thermal Insights" (17K)
              * Structure: UV glow + shadow zone + reactivation (3 separate concepts)
              * Too scattered—each concept needed its own video
              * Result: Confusing, no clear spine
            
            The Spine Test:
            
            Can you name the ONE thing this video is about in 3-4 words?
            
            Good Spines:
            - "The hesitation zone"
            - "Winter's thermal hub"
            - "The shadow pattern"
            - "The thermal switch"
            
            Bad (List Brain):
            - "Rut hunting tips"
            - "Scrape science"
            - "Cold front strategies"
            - "Bedding mistakes"
            
            If you need more than 4 words, it's probably List Brain.
            
            Implementation Rules:
            
            1. NO NUMBERED LISTS IN FIRST HALF
               Bad: "Here are 5 mistakes hunters make during the rut..."
               Good: "This mistake cost me Thunder. I made it three times before I realized..."
            
            2. SAME BEHAVIOR, MULTIPLE CONTEXTS
               Example - Hesitation Zone Spine:
               - Context 1: Does feeding on kudzu, ignoring corn
               - Context 2: Buck approaching, stopping at 32 yards
               - Context 3: Same buck, night 2, stops at 28 yards
               - Context 4: Different buck, stops at 35 yards
               - Context 5: Pattern revealed: 25-50 yard zone across all deer
               
               Same spine (hesitation), five appearances, escalating proof.
            
            3. ESCALATION PATTERN
               Each spine appearance should:
               - First: Introduce the behavior (curious, unexplained)
               - Second: Confirm it's not a fluke (pattern emerging)
               - Third+: Add new context (different conditions, different deer)
               - Final: Reveal the pattern with data/measurement
            
            4. NO DRIFT TO TEACHING MODE
               Video must maintain spine focus throughout. Don't let it branch:
               
               Bad progression:
               - Start: Hesitation zone mystery
               - Middle: Drift into "3 other corn mistakes"
               - End: General baiting tips
               
               Good progression:
               - Start: Hesitation zone mystery
               - Middle: More hesitation zone examples
               - End: What hesitation zone means for stand placement
            
            The List Brain Temptation:
            
            AI naturally wants to organize into lists because it feels "comprehensive." Resist this. Lists feel:
            - Replaceable (could get same tips elsewhere)
            - Skippable (viewer cherry-picks)
            - Padded (points 3-5 feel like filler)
            - Repetitive (AI restates same concept multiple ways)
            
            Single Spine feels:
            - Unique (this specific behavior, this specific footage)
            - Essential (each appearance builds on last)
            - Tight (no room for filler)
            - Focused (same idea deepening, not spreading)
            
            Common Spine Examples:
            
            Behavioral Spines:
            - Hesitation zone (deer stopping at specific distance)
            - Shadow pattern (deer approaching from non-wind side)
            - Thermal switch (deer standing at specific temperature)
            - Orbiting behavior (deer circling but not approaching)
            - Displacement pattern (morning vs evening movement)
            
            Character Spines:
            - Named buck's territory (Winter's thermal hub)
            - Named buck's quirk (limping but dominant)
            - Specific buck's violation of pattern (why did he change?)
            
            Test Spines:
            - 7-night corn study (same test, nightly results)
            - E-bike bump recovery (same deer, before/after)
            - Cold front tracking (same buck, warm vs cold day)
            
            Spine Visualization:
            
            Think of your video as following ONE thread that appears multiple times, not multiple separate threads:
            
            Single Spine (strong):
            ━━━━━━━━━━━━━━━━━━━━━━━━━
              ↓      ↓      ↓      ↓
            (same behavior, 4 contexts)
            
            List Brain (weak):
            ━━━ ━━━ ━━━ ━━━ ━━━
             #1  #2  #3  #4  #5
            (5 separate ideas)
            
            The first creates momentum. The second creates scatter.
            
            When List Format IS Appropriate:
            
            Only use lists when:
            - You're creating a reference/utility video (knowingly sacrificing entertainment for utility)
            - It's a tactical recap AFTER the spine investigation is complete
            - The list items are all variations of the same spine (not separate concepts)
            
            Example of acceptable list use:
            After establishing hesitation zone as spine, you could end with:
            "So based on the hesitation zone pattern, here are 3 tactical changes:
            1. Hunt 25-50 yards off bait (not over it)
            2. Position where hesitation zone overlaps trails
            3. Expect 15+ minute evaluation period before approach"
            
            This works because all 3 points stem from the single spine—they're applications, not separate concepts.
            """,
            checkPrompt: """
            Analyze this script for Single Spine vs List Brain:

            {{SCRIPT}}

            Single Spine = one central behavioral mystery that repeats and escalates
            List Brain = multiple separate tips/concepts that scatter focus

            Rate this script 1-10 on Single Spine (1 = scattered list, 10 = tight spine focus), then analyze:

            1. SPINE IDENTIFICATION: Can you name the ONE central behavior/phenomenon in 3-4 words?
               - If yes: Quote it and list how many times it appears in the script
               - If no: This is List Brain—explain why no clear spine exists

            2. NUMBERED LIST CHECK: Flag any numbered lists in the first half:
               - "5 mistakes..."
               - "3 reasons..."
               - "7 tips..."
               Numbered lists indicate List Brain unless they all stem from one spine.

            3. REPETITION PATTERN: Does the same behavior appear 3+ times in different contexts?
               - Context 1: [quote where behavior first appears]
               - Context 2: [quote where behavior repeats]
               - Context 3+: [quote additional appearances]
               If behavior doesn't repeat, there's no spine.

            4. ESCALATION TEST: Do spine appearances build on each other?
               - First appearance: Introduces behavior
               - Second: Confirms pattern
               - Third+: Adds new context or measurement
               Or does each section introduce something new and unrelated?

            5. DRIFT CHECK: Does the script maintain spine focus throughout, or does it branch into multiple separate concepts?
               Quote where drift occurs if present.

            6. MEMORY ANCHOR: What would a viewer call this video 6 months later?
               - Single Spine: "The hesitation zone video" (specific, memorable)
               - List Brain: "That video with hunting tips" (generic, forgettable)

            Provide your rating and specific quotes. If score is below 6, explain how List Brain is killing focus and memory.
            """,
            fixPrompt: """
            Rewrite this script to enforce Single Spine structure:

            {{SCRIPT}}

            Your task: Consolidate around ONE central behavioral mystery. Follow these rules:

            1. IDENTIFY THE STRONGEST SPINE:
               Look for the most compelling behavioral pattern in the current script. This becomes your spine. Everything else gets cut or subordinated.
               
            2. REMOVE ALL NUMBERED LISTS FROM FIRST HALF:
               Delete: "Here are 5 mistakes..." or "3 reasons why..."
               Replace with: Focus on the spine behavior appearing in multiple contexts

            3. CREATE SPINE APPEARANCES (minimum 3):
               Show the same behavior in different contexts:
               - Different nights/days
               - Different deer (but same behavior)
               - Different conditions (warm vs cold, etc.)
               Each appearance should add new detail without repeating.

            4. BUILD ESCALATION:
               - First appearance: "Here's something weird I noticed..."
               - Second: "It happened again..."
               - Third: "This is a pattern..."
               - Fourth+: "Here's the measurement/data..."

            5. ELIMINATE DRIFT:
               If script branches into separate concepts, cut them. One video = one spine. Other concepts become future video ideas.

            6. END WITH SPINE APPLICATIONS (not separate tips):
               Instead of "5 unrelated tips," give "3 ways to use [spine discovery]"
               Example: "Based on the hesitation zone pattern: 1) Hunt off the bait, 2) Position in the zone, 3) Expect 15min evaluations"

            Output the rewritten script with [SPINE: ...] tags marking each appearance of the central behavior. Cut ruthlessly—better to have one strong spine than multiple weak threads.
            """,
            suggestionsPrompt: """
            Identify List Brain weaknesses in this script:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to consolidate into Single Spine. For each:

            FORMAT:
            CURRENT: [Quote the scattered/list-based section]
            IMPROVED: [Show single-spine version]
            WHY: [Explain how this increases focus and memory]

            Focus on:
            1. Numbered lists that should be consolidated into one repeating behavior
            2. Multiple separate concepts that should be saved for different videos
            3. Spine behavior that appears once but should appear 3+ times
            4. Drift from initial spine into unrelated territory
            5. Endings that list separate tips instead of applying the spine

            Prioritize ruthless consolidation—one strong spine beats five weak concepts.
            """
        ),

        ScriptGuideline(
            category: .derrick,
            title: "Concrete Language",
            summary: "Use specific times, distances, and names instead of vague descriptions—precision builds authority.",
            explanation: """
            Concrete Language means replacing every vague, generic description with specific, measurable, named details. This builds authority, creates visual clarity, and makes your content memorable and quotable.
            
            This is a polish-layer guideline—it won't prevent disasters like the core 5, but it elevates good scripts to great by making them feel professional, precise, and credible.
            
            Vague Language feels amateur:
            - "Later that morning..."
            - "Far away from the bedding area..."
            - "The ridge..."
            - "A mature buck..."
            - "Moving quickly..."
            - "After resting briefly..."
            
            Concrete Language feels authoritative:
            - "9:47 AM..."
            - "340 yards from the thermal hub..."
            - "Thermal Hub Ridge..."
            - "Winter, the 160-inch 8-point..."
            - "Busting absolute tail..."
            - "After a lightning-fast 10-minute catnap..."
            
            The difference: Vague language could describe anyone's observations. Concrete language signals "I measured this precisely, I know this property intimately, I've studied this individual deer extensively."
            
            The Six Concrete Language Replacements:
            
            1. TIME SPECIFICITY
               Vague: "later that morning," "around midday," "in the afternoon"
               Concrete: "9:47 AM," "1:23 PM," "4:15 PM"
               
               Why: Specific times signal you were actually tracking in real-time, not summarizing generally
            
            2. DISTANCE PRECISION
               Vague: "far away," "close to," "not too far from"
               Concrete: "340 yards," "28 yards," "within 50 yards"
               
               Why: Measurement builds credibility and helps viewers visualize scale
            
            3. LOCATION NAMING
               Vague: "the ridge," "a bedding area," "near the food source"
               Concrete: "Thermal Hub Ridge," "the north drainage convergence," "the white oak flat"
               
               Why: Named locations signal intimate property knowledge and create memorable mental maps
            
            4. DEER IDENTIFICATION
               Vague: "a mature buck," "the deer," "another buck"
               Concrete: "Winter, the 160-inch 8-point with the limp," "the split-G2 4-year-old," "Phantom"
               
               Why: Named deer with traits become characters viewers remember and care about
            
            5. MOVEMENT DESCRIPTION (Active Verbs + Personality)
               Vague: "moving quickly," "walking slowly," "resting briefly," "eating"
               Concrete: "busting absolute tail," "mosying cautiously," "lightning-fast catnap," "browsing nervously"
               
               Why: Personality-infused descriptions are entertaining and paint clearer mental pictures
            
            6. BEHAVIOR QUANTIFICATION
               Vague: "many times," "repeatedly," "often," "rarely"
               Concrete: "47 times across 6 months," "14 consecutive mornings," "twice in 200 hours," "3 times out of 17 sits"
               
               Why: Numbers create credibility and help viewers understand pattern strength
            
            Examples Contrasted:
            
            VAGUE PARAGRAPH:
            "Later that morning, the buck moved from his bedding area toward the food source. He stopped far away and seemed cautious. After resting briefly, he continued moving slowly. I've seen this behavior many times with mature bucks on this property."
            
            CONCRETE PARAGRAPH:
            "9:47 AM. Winter left the Thermal Hub Ridge and moved south toward the white oak flat—340 yards of exposed travel. At 32 yards from the oaks, he stopped. Stared. Four minutes of evaluating before taking another step. After a lightning-fast 10-minute catnap in the finger ridge, he mosied the final 40 yards. I've documented this hesitation pattern 14 times out of 17 morning movements."
            
            The concrete version:
            - Paints clearer mental picture
            - Feels more credible (specific measurements)
            - Creates memorable details (10-minute catnap, 32-yard stop)
            - Signals deep property/deer knowledge
            - Is quotable ("the 10-minute catnap," "32-yard hesitation")
            
            When Concrete Language Matters Most:
            
            1. OPENING SEQUENCES
               First impression of authority—vague opening signals amateur
               
            2. KEY BEHAVIORAL MOMENTS
               When describing the spine behavior, precision emphasizes importance
               
            3. DATA PRESENTATIONS
               When sharing findings, specific numbers trump "often" or "usually"
               
            4. CHARACTER INTRODUCTIONS
               Named deer with specific traits become memorable protagonists
            
            Common Concrete Language Patterns:
            
            Time Patterns:
            - "6:47 AM" not "early morning"
            - "November 8th, 2:15 PM" not "one afternoon in November"
            - "4 minutes and 23 seconds" not "a few minutes"
            
            Distance Patterns:
            - "28 yards" not "close"
            - "1,200 yards" not "over half a mile"
            - "Within 50 yards" not "nearby"
            
            Location Patterns:
            - "Thermal Hub Ridge" not "the main bedding ridge"
            - "White Oak Flat #3" not "one of the food sources"
            - "North drainage convergence" not "a low spot"
            
            Deer Patterns:
            - "Winter, 160-inch 8-point, limping front right" not "a big mature buck"
            - "The split-G2 4-year-old" not "a younger buck"
            - "Phantom, the 47-acre ghost" not "an elusive deer"
            
            Movement Patterns:
            - "Busting absolute tail" not "running fast"
            - "Mosying cautiously" not "walking slowly"
            - "Lightning-fast catnap" not "brief rest"
            - "Browsing nervously" not "eating"
            
            Quantity Patterns:
            - "47 times in 200 hours" not "many times"
            - "14 consecutive mornings" not "every morning for a while"
            - "3 out of 17 sits" not "occasionally"
            
            Why This Is Polish, Not Core:
            
            A script can succeed without perfect concrete language IF it has:
            - High ownership
            - Event framing
            - Evidence-first structure
            - Sustained uncertainty
            - Single spine
            
            Example: Your Corn video (474K) probably didn't have perfect concrete language throughout, but it succeeded on core principles.
            
            However, adding concrete language to an already-solid script:
            - Increases perceived authority
            - Improves retention (clearer mental pictures = easier to follow)
            - Makes content more quotable/shareable
            - Elevates production quality feel
            
            Think of it as the difference between:
            - Amateur: "I saw a buck near my corn"
            - Professional: "November 4th, 6:47 PM. The 8-point approached within 32 yards of the corn pile, stopped, evaluated for 4 minutes, then disappeared into the north drainage."
            
            Both describe the same event. The second feels like serious research.
            
            Implementation Checklist:
            
            During script review, search for:
            - [ ] "Later," "around," "about" → Replace with specific times
            - [ ] "Far," "close," "near" → Replace with yard measurements
            - [ ] "The ridge," "the area," "the spot" → Replace with named locations
            - [ ] "A buck," "the deer," "another one" → Replace with named individuals
            - [ ] "Quickly," "slowly," "briefly" → Replace with personality descriptions
            - [ ] "Many," "often," "rarely" → Replace with specific counts
            
            AI Tendency:
            AI loves vague language because it feels "safer" and more general. You must actively force concrete replacements during editing.
            """,
            checkPrompt: """
            Analyze this script for Concrete Language:

            {{SCRIPT}}

            Concrete Language = specific times, distances, names, measurements
            Vague Language = "later," "far away," "the ridge," "a buck," "quickly"

            Rate this script 1-10 on Concrete Language (1 = entirely vague, 10 = precisely specific), then analyze:

            1. TIME VAGUENESS: Flag all vague time references:
               - "Later that morning," "around noon," "in the afternoon"
               Count instances. Are specific times used (9:47 AM) or vague descriptions?

            2. DISTANCE VAGUENESS: Flag all vague distance references:
               - "Far away," "close to," "near," "not too far"
               Count instances. Are measurements used (340 yards, 28 yards)?

            3. LOCATION VAGUENESS: Flag generic location references:
               - "The ridge," "the bedding area," "a field edge"
               Are locations named (Thermal Hub Ridge, White Oak Flat)?

            4. DEER VAGUENESS: How are deer referenced?
               - Generic: "a mature buck," "the deer," "another buck"
               - Concrete: "Winter, the 160-inch 8-point," "the split-G2 4-year-old"
               Count generic vs named references.

            5. MOVEMENT VAGUENESS: How is deer movement described?
               - Vague: "moving quickly," "walking slowly," "resting"
               - Concrete: "busting absolute tail," "mosying cautiously," "lightning-fast catnap"
               Quote examples of each.

            6. QUANTITY VAGUENESS: How are patterns quantified?
               - Vague: "many times," "often," "rarely"
               - Concrete: "47 times in 200 hours," "14 consecutive mornings"
               Quote examples of each.

            Provide your rating and count vague instances in each category. If score is below 7, list the most critical vague phrases to replace.
            """,
            fixPrompt: """
            Rewrite this script to maximize Concrete Language:

            {{SCRIPT}}

            Your task: Replace every vague description with specific, measurable, named details. Follow these rules:

            1. REPLACE TIME VAGUENESS:
               - "Later that morning" → "9:47 AM"
               - "Around midday" → "12:23 PM"
               - "In the afternoon" → "3:15 PM"
               Add specific times to every major event.

            2. REPLACE DISTANCE VAGUENESS:
               - "Far away" → "340 yards"
               - "Close to" → "28 yards"
               - "Near" → "within 50 yards"
               Provide specific measurements for all spatial references.

            3. NAME ALL LOCATIONS:
               - "The ridge" → "Thermal Hub Ridge"
               - "A bedding area" → "The north drainage convergence"
               - "Near the food source" → "40 yards from White Oak Flat #3"
               Create property-specific names that signal intimate knowledge.

            4. NAME AND CHARACTERIZE DEER:
               - "A mature buck" → "Winter, 160-inch 8-point with limping front right"
               - "The deer" → "Phantom, the 47-acre ghost"
               - "Another buck" → "The split-G2 4-year-old"
               Give every featured deer a name and specific physical traits.

            5. ADD PERSONALITY TO MOVEMENT:
               - "Moving quickly" → "Busting absolute tail"
               - "Walking slowly" → "Mosying cautiously"
               - "Resting briefly" → "Lightning-fast 10-minute catnap"
               Use active, vivid descriptions.

            6. QUANTIFY ALL PATTERNS:
               - "Many times" → "47 times across 6 months"
               - "Often" → "14 consecutive mornings"
               - "Rarely" → "3 times out of 17 sits"
               Replace every "often/many/rarely" with specific counts.

            Output the rewritten script with [CONCRETE: ...] tags marking each vague-to-concrete replacement.
            """,
            suggestionsPrompt: """
            Identify vague language weaknesses in this script:

            {{SCRIPT}}

            Provide 3-5 specific suggestions to increase Concrete Language. For each:

            FORMAT:
            CURRENT: [Quote the vague phrase]
            IMPROVED: [Show concrete replacement]
            WHY: [Explain how specificity increases authority/clarity]

            Focus on:
            1. Time references that need specific timestamps
            2. Distance references that need yard measurements
            3. Generic location names that should be property-specific
            4. Unnamed deer that need names and physical traits
            5. Bland movement descriptions that need personality
            6. Pattern descriptions using "often/many" instead of counts

            Prioritize the most impactful replacements—ones that would most increase perceived authority and precision.
            """
        )
        
    ]
}
