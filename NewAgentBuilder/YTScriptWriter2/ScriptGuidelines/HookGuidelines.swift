//
//  HookGuidelines.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

import Foundation

extension ScriptGuidelinesDatabase {
    static var hooksGuidelines: [ScriptGuideline] = [
        
        ScriptGuideline(
            category: .hooks,
            title: "Value in First 10 Seconds",
            summary: "Deliver meaningful insight within the first 10 seconds, not just setup",
            explanation: """
            Don't make viewers wait for value. The first 10 seconds should contain:
            - A specific insight, data point, or contrarian take
            - NOT just "I'm going to tell you about..."
            - NOT just "Here's what happened..."
            
            Example:
            ❌ "Today I'm going to show you why food plots aren't holding bucks"
            ✅ "This property pulls in 50% of all deer in the area—but zero mature bucks bed here during daylight. Here's why."
            """,
            checkPrompt: """
            Check if this script delivers value in the first 10 seconds:
            
            {{SCRIPT}}
            
            1. Quote the first 10 seconds (roughly 25-30 words)
            2. Does it contain a specific insight/data point? Yes/No
            3. Or is it just setup/promise? 
            4. Rate 1-10 on immediate value delivery
            """,
            fixPrompt: """
            Rewrite the opening to deliver value within first 10 seconds:
            
            {{SCRIPT}}
            
            Rules:
            - First 25-30 words must contain specific insight or data
            - No "I'm going to tell you about..." 
            - No generic setup
            - Lead with the most interesting fact
            
            Rewrite just the opening, keep the rest.
            """,
            suggestionsPrompt: """
            Suggest 2-3 ways to front-load value in the opening:
            
            {{SCRIPT}}
            
            For each option:
            - Pull the most interesting data/insight from later
            - Show how to lead with it in first 10 seconds
            - Explain why this hooks better
            """
        ),
        
        ScriptGuideline(
            category: .hooks,
            title: "Open Loops (Create Hunts)",
            summary: "Tease valuable information throughout to maintain tension",
            explanation: """
            Create information gaps that viewers need to close:
            
            - "And here's where it gets interesting..."
            - "But that's not the surprising part..."
            - "What we found next changed everything..."
            
            Don't give away all answers immediately. Make them want to keep watching.
            
            BAD: Linear delivery with no tension
            GOOD: Strategic reveals that build curiosity
            """,
            checkPrompt: """
            Check for open loops / information hunts in this script:
            
            {{SCRIPT}}
            
            1. Identify places where script teases upcoming info
            2. Mark sections that deliver everything upfront
            3. Count how many "hunts" are created
            4. Rate 1-10 on tension maintenance
            """,
            fixPrompt: """
            Add open loops to create more tension:
            
            {{SCRIPT}}
            
            Rules:
            - Add 3-5 teases that hint at coming insights
            - Don't give away conclusions before showing evidence
            - Create "and here's what we found next..." moments
            - Maintain factual accuracy while building tension
            """,
            suggestionsPrompt: """
            Suggest 2-3 places to add open loops:
            
            {{SCRIPT}}
            
            For each:
            - Quote where conclusion is stated too early
            - Show the tease to add before it
            - Show the delayed reveal
            """
        ),
        
        // Add more hooks guidelines here...
    ]
}
