//
//  VoiceGuidelines.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/31/25.
//

import Foundation

extension ScriptGuidelinesDatabase {
    static var voiceGuidelines: [ScriptGuideline] = [
        
        ScriptGuideline(
            category: .voice,
            title: "Audience of One (You, Not You Guys)",
            summary: "Write to one person using 'you', not to a crowd using 'you guys' or third person",
            explanation: """
            Write like you're explaining to ONE hunting buddy at camp.
            
            BAD:
            - "You guys might have experienced this..."
            - "Hunters often see this pattern..."
            - Third person: "The property owner noticed..."
            
            GOOD:
            - "You might have experienced this..."
            - "If you're managing a property..."
            - "Your trail cameras probably show..."
            
            Exception: When telling someone else's story, use their name, but then pivot to "you" when applying lessons.
            """,
            checkPrompt: """
            Check "Audience of One" language in this script:
            
            {{SCRIPT}}
            
            1. Count uses of "you" vs "you guys" vs third person
            2. Identify sections that feel like crowd address
            3. Mark places that should be more intimate
            4. Rate 1-10 on one-to-one feeling
            """,
            fixPrompt: """
            Rewrite to speak to one person (audience of one):
            
            {{SCRIPT}}
            
            Changes:
            - Replace "you guys" with "you"
            - Replace "hunters" with "you"
            - Replace crowd language with intimate language
            - Keep third person only when telling someone else's story
            """,
            suggestionsPrompt: """
            Suggest 2-3 places to make language more intimate:
            
            {{SCRIPT}}
            
            For each:
            - Quote the crowd-addressing language
            - Rewrite as one-to-one conversation
            - Explain why this feels more personal
            """
        ),
        
        // Add more voice guidelines here...
    ]
}
