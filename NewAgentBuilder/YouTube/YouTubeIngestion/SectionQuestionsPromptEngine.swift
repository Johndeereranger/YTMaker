//
//  SectionQuestionsPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/29/26.
//

import Foundation

/// Builds LLM prompts for the "What questions does this section answer?" analysis.
/// Single prompt type — no enum needed.
struct SectionQuestionsPromptEngine {

    // MARK: - System Prompt

    static func buildSystemPrompt() -> String {
        """
        You are a content structure analyst studying YouTube video scripts. You will receive a single section from a video script along with its rhetorical classification. Your job is to identify the QUESTIONS that this section answers for the viewer.

        ## INSTRUCTIONS

        Read the transcript section carefully. Identify every question — explicit or implicit — that a viewer would have answered after reading/hearing this section. These are the questions the section RESOLVES, not questions it RAISES.

        ## OUTPUT FORMAT

        For each question:
        1. **The Question**: State the question clearly and specifically
        2. **How It's Answered**: A 1-sentence summary of how the section answers it
        3. **Supporting Text**: Quote the specific sentence(s) from the transcript that provide the answer

        ## RULES

        - Questions must be answerable FROM the section text provided — do not infer questions answered by content not shown
        - Include both explicit questions (the narrator asks and answers) and implicit questions (the section provides information that resolves a viewer curiosity)
        - Order questions from most prominent/central to most peripheral
        - Be specific — "What happened?" is too vague; "What caused the bridge collapse in 1967?" is specific
        - Every question listed must have supporting text quoted directly from the transcript
        - If the section is primarily atmospheric or transitional and answers very few questions, say so explicitly rather than inventing questions
        - Do NOT list questions that the section RAISES but does not answer — only list questions that are RESOLVED within this section
        - The questions should reflect what the viewer LEARNS from this section, not what the narrator intends to do
        """
    }

    // MARK: - User Prompt

    static func buildUserPrompt(
        input: SectionQuestionInput,
        creatorName: String
    ) -> String {
        """
        ## CREATOR
        \(creatorName)

        ## VIDEO
        \(input.videoTitle)

        ## SECTION POSITION
        Chunk #\(input.chunkIndex) — \(input.position.displayName) of script

        ## RHETORICAL MOVE
        \(input.moveType.displayName) (\(input.moveType.rawValue))
        Definition: \(input.moveType.rhetoricalDefinition)

        ## SECTION SUMMARY
        \(input.briefDescription)

        ## RAW TRANSCRIPT TEXT

        \(input.sectionText)

        ---

        Identify all questions that this section answers for the viewer. Ground every answer in direct quotes from the transcript above.
        """
    }

    // MARK: - LLM Parameters

    static func defaultParams() -> [String: Any] {
        ["temperature": 0.2, "max_tokens": 4000]
    }
}
