//
//  PacingGuidelines.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

import Foundation

extension ScriptGuidelinesDatabase {
    static var pacingGuidelines: [ScriptGuideline] = [
        
        ScriptGuideline(
            category: .pacing,
            title: "Sentence Rhythm (Jagged Margin)",
            summary: "Vary sentence length dramatically - short, medium, long, short creates rhythm",
            explanation: """
            Monotone sentence length = monotone delivery.
            
            BAD: All sentences roughly same length (15-20 words)
            GOOD: Mix of 3-word, 12-word, 25-word, 5-word sentences
            
            Pattern to aim for:
            - Short (3-7 words)
            - Medium (10-15 words)
            - Long (20-30 words)
            - Short (3-7 words)
            
            Visual test: If your script's right margin looks straight, rhythm is flat.
            """,
            checkPrompt: """
            Analyze sentence rhythm in this script:
            
            {{SCRIPT}}
            
            For each sentence:
            1. Count words per sentence
            2. Identify monotone sections (same length repeatedly)
            3. Calculate standard deviation
            4. Rate 1-10 on rhythm variation
            """,
            fixPrompt: """
            Improve sentence rhythm variation:
            
            {{SCRIPT}}
            
            Rules:
            - Break long monotone stretches
            - Add punchy short sentences for emphasis
            - Combine short choppy sequences into flowing longer ones
            - Aim for jagged right margin visually
            - Keep all facts, just vary structure
            """,
            suggestionsPrompt: """
            Suggest 2-3 places to improve rhythm:
            
            {{SCRIPT}}
            
            For each:
            - Quote monotone section
            - Show before/after with varied lengths
            - Explain pacing impact
            """
        ),
        
        // Add more pacing guidelines here...
    ]
}
