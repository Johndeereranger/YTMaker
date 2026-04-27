//
//  StructureGuidelines.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

import Foundation

extension ScriptGuidelinesDatabase {
    static var structureGuidelines: [ScriptGuideline] = [
        
        ScriptGuideline(
            category: .structure,
            title: "But/Therefore (Not And Then)",
            summary: "Story should progress through conflict and consequence, not just sequential events",
            explanation: """
            The "But/Therefore" rule (from South Park creators):
            
            BAD: "This happened AND THEN this happened AND THEN this happened"
            GOOD: "This happened BUT this happened THEREFORE this happened"
            
            Each beat should create tension (BUT) or consequence (THEREFORE).
            "And then" is just a list - no narrative drive.
            
            Example:
            ❌ "I flew the property and then found 20 deer and then noticed they were all does"
            ✅ "I flew the property expecting to find bucks bedded, BUT all 20 deer were does, THEREFORE we needed to expand the search to neighboring properties"
            """,
            checkPrompt: """
            Analyze this script for "But/Therefore" story progression:
            
            {{SCRIPT}}
            
            1. Identify sequences that use "and then" style progression
            2. Mark which story beats have tension (BUT) or consequence (THEREFORE)
            3. Rate the script 1-10 on narrative drive vs. list-making
            4. List 3-5 specific moments that feel like "and then"
            """,
            fixPrompt: """
            Rewrite this script to use "But/Therefore" progression instead of "And Then":
            
            {{SCRIPT}}
            
            Rules:
            - Each beat should create conflict (BUT) or consequence (THEREFORE)
            - Remove sequential "and then" transitions
            - Make story progress through tension and resolution
            - Maintain all facts and data, just restructure flow
            
            Output the rewritten script sentence by sentence.
            """,
            suggestionsPrompt: """
            Given this script, suggest 2-3 specific places where "But/Therefore" structure could strengthen the narrative:
            
            {{SCRIPT}}
            
            For each suggestion:
            - Quote the current "and then" sequence
            - Show how to rewrite with "but/therefore"
            - Explain why this creates better tension
            """
        ),
        
        ScriptGuideline(
            category: .structure,
            title: "Story Loops (Context → Reveal)",
            summary: "Every section should set up context, then deliver a reveal that exceeds expectations",
            explanation: """
            Structure content as micro story loops:
            
            CONTEXT: Set up what the audience expects or believes
            REVEAL: Deliver something better/more specific/unexpected
            
            BAD: Just stating facts without setup
            GOOD: Building expectation, then exceeding it
            
            Example:
            ❌ "The property had 20 deer"
            ✅ "Most hunters would call this property finished. But when I flew it, I found something they couldn't see from the ground..."
            """,
            checkPrompt: """
            Check if this script uses story loops (Context → Reveal):
            
            {{SCRIPT}}
            
            For each section:
            1. Identify the CONTEXT (what expectation is set)
            2. Identify the REVEAL (what insight exceeds that expectation)
            3. Mark sections that lack proper setup
            4. Rate 1-10 on how well reveals pay off
            """,
            fixPrompt: """
            Rewrite this script to add story loops (Context → Reveal) to each section:
            
            {{SCRIPT}}
            
            For each major point:
            - Add CONTEXT that sets up audience expectation
            - Deliver REVEAL that exceeds what they expected
            - Make sure reveal is better/more specific, never worse
            
            Maintain all facts, just add setup/payoff structure.
            """,
            suggestionsPrompt: """
            Suggest 2-3 places where adding story loops would strengthen this script:
            
            {{SCRIPT}}
            
            For each:
            - Quote the current flat statement
            - Show the CONTEXT setup to add before it
            - Show the enhanced REVEAL
            """
        ),
        
        // Add more structure guidelines here...
    ]
}
