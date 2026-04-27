//
//  ScriptTraceW5Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation

// MARK: - W5: Seam Check Service

/// Checks and fixes connective seams between adjacent beats.
/// Can ONLY: add 1-3 word connective, period->dash, adjust pronoun.
/// CANNOT: rewrite, add content, change structure.
class ScriptTraceW5Service {
    private let adapter = ClaudeModelAdapter(model: .claude35Sonnet)

    // MARK: - Seam Result

    struct SeamResult {
        let editDescription: String?    // nil if no edit needed
        let finalText: String           // Text with seam applied (or unchanged)
    }

    // MARK: - Check Seam

    /// Check the transition between the previous beat's text and the current beat's text.
    /// Returns the current beat's text with any seam edit applied.
    func checkSeam(
        previousText: String,
        currentText: String
    ) async -> SeamResult {
        let userPrompt = """
        PREVIOUS SENTENCE: "\(previousText)"
        CURRENT SENTENCE: "\(currentText)"

        These are two consecutive sentences in a script, each adapted from different source material.
        Check if the transition feels abrupt.

        You may ONLY:
        - Add 1-3 word connective to the start of the current sentence ("But", "And", "So", "Now")
        - Replace the period at the end of the previous sentence with a dash
        - Adjust a pronoun referent in the current sentence

        You CANNOT:
        - Rewrite either sentence
        - Add new content
        - Change sentence structure

        If no edit is needed, return: {"edit": null, "text": "<current sentence unchanged>"}
        If an edit is needed, return: {"edit": "<description of what you changed>", "text": "<current sentence with edit applied>"}

        Return ONLY the JSON.
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: "You are a seam editor. You make minimal connective fixes between script beats.",
            params: ["temperature": 0.1, "max_tokens": 500]
        )

        return parseSeamResult(response, fallbackText: currentText)
    }

    // MARK: - Batch Seam Check

    /// Check seams for all beats in sequence. Returns updated texts.
    func checkAllSeams(texts: [String]) async -> [(editDescription: String?, finalText: String)] {
        var results: [(String?, String)] = []

        for i in 0..<texts.count {
            if i == 0 {
                // First beat has no seam to check
                results.append((nil, texts[i]))
            } else {
                let result = await checkSeam(previousText: texts[i - 1], currentText: texts[i])
                results.append((result.editDescription, result.finalText))
            }
        }

        return results
    }

    // MARK: - Parse Response

    private func parseSeamResult(_ response: String, fallbackText: String) -> SeamResult {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SeamResult(editDescription: nil, finalText: fallbackText)
        }

        let edit = json["edit"] as? String
        let text = json["text"] as? String ?? fallbackText

        return SeamResult(editDescription: edit, finalText: text)
    }
}
