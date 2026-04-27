//
//  Phase0AnalysisService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import Foundation

/// Service for running Phase 0 structural analysis on video transcripts
/// Extracts EXECUTION TRACES (literal descriptions) for template compatibility testing
class Phase0AnalysisService {

    static let shared = Phase0AnalysisService()

    // MARK: - Main Analysis Function

    /// Analyze a transcript to extract execution trace
    func analyzeTranscript(transcript: String, title: String, duration: String = "") async throws -> Phase0Result {
        return try await analyzeTranscriptParallel(transcript: transcript, title: title, duration: duration, temperature: 0.2)
    }

    /// Analyze transcript with fresh adapter for parallel execution
    func analyzeTranscriptParallel(transcript: String, title: String, duration: String = "", temperature: Double = 0.2) async throws -> Phase0Result {
        // Create fresh adapter for this call to enable true parallel execution
        let freshAdapter = ClaudeModelAdapter(model: .claude4Sonnet)

        // Truncate transcript if too long (keep first ~15000 chars for token limits)
        let truncatedTranscript = String(transcript.prefix(15000))
        let wasTruncated = transcript.count > 15000

        // Format duration for display
        let durationDisplay = formatDurationForPrompt(duration)
        let durationSeconds = parseDurationToSeconds(duration)

        let prompt = """
        Analyze this YouTube video transcript to extract its EXECUTION TRACE.

        VIDEO TITLE: \(title)
        VIDEO DURATION: \(durationDisplay) (~\(durationSeconds) seconds)
        TRANSCRIPT\(wasTruncated ? " (truncated)" : ""):
        \(truncatedTranscript)

        ═══════════════════════════════════════════════════════════════
        EXECUTION TRACE (Required for clustering)
        ═══════════════════════════════════════════════════════════════

        Describe what LITERALLY HAPPENS. No category labels. No vibes.
        This will be used to test: "If an AI used this video's structure as a template for a different topic, where would it BREAK?"

        ### Opening (first 60-90 seconds)
        - durationSeconds: How many seconds before the first major shift/pivot?
        - whatHappens: Describe LITERALLY what the viewer sees/hears (not interpretation)
        - hookType: Exactly one of: "question" | "frustration" | "mystery" | "promise"

        ### Pivots (each mental model shift)
        A pivot is when the viewer's mental model is FORCED to change.
        Test: "Wrong understanding vs incomplete understanding?" Wrong = pivot.

        For EACH pivot:
        - pivotNumber: 1, 2, 3...
        - timestampPercent: Approximate % through video (0-100)
        - triggerMoment: Quote or paraphrase the EXACT sentence that forces the shift
        - assumptionChallenged: What assumption does this pivot explicitly contradict?

        ### Evidence Flow
        List evidence types in the ORDER they appear (sequence matters for template compatibility):
        Example: ["personal-anecdote", "industry-stat", "expert-quote", "historical-example", "visual-demonstration"]

        ### Escalation
        One sentence: How do stakes/mystery/complexity LITERALLY increase through the video?

        ### Resolution
        What LITERALLY happens in the final 2-3 minutes? How does it close?

        ### Narrator Role
        Exactly one of:
        - "character-in-story": Creator is a character within the narrative
        - "detached-analyst": Creator analyzes from outside, objective voice
        - "on-location-explorer": Creator physically explores/investigates
        - "personal-confessor": Creator shares personal experience/journey

        ═══════════════════════════════════════════════════════════════

        Return ONLY valid JSON matching this exact schema:
        {
          "opening": {
            "durationSeconds": integer,
            "whatHappens": string,
            "hookType": string
          },
          "pivots": [
            {
              "pivotNumber": integer,
              "timestampPercent": integer,
              "triggerMoment": string,
              "assumptionChallenged": string
            }
          ],
          "evidenceFlow": string[],
          "escalation": string,
          "resolution": string,
          "narratorRole": string
        }
        """

        let systemPrompt = """
        You are extracting EXECUTION TRACES from video transcripts.

        CRITICAL: Focus on what LITERALLY HAPPENS, not interpretations or category labels.

        Your output will be used for TEMPLATE COMPATIBILITY TESTING:
        "If an AI used Video A's execution trace to write Video B, where would the structure BREAK?"

        Rules:
        1. Quote or paraphrase actual moments from the transcript for pivot triggers
        2. Evidence flow must be ORDERED (sequence matters for template compatibility)
        3. Opening/resolution describe LITERAL events, not vibes or feelings
        4. No abstract labels like "escalating stakes" - describe HOW stakes escalate
        """

        let response = await freshAdapter.generate_response(
            prompt: prompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 2000]
        )

        return try parseAnalysisResponse(response: response)
    }

    /// Format ISO 8601 duration (PT15M30S) to human readable
    private func formatDurationForPrompt(_ duration: String) -> String {
        guard !duration.isEmpty else { return "Unknown" }

        var result: [String] = []
        var current = ""

        for char in duration {
            if char.isNumber {
                current += String(char)
            } else if char == "H", let hours = Int(current) {
                result.append("\(hours) hour\(hours == 1 ? "" : "s")")
                current = ""
            } else if char == "M", let mins = Int(current) {
                result.append("\(mins) minute\(mins == 1 ? "" : "s")")
                current = ""
            } else if char == "S", let secs = Int(current) {
                if result.isEmpty {
                    result.append("\(secs) seconds")
                }
                current = ""
            }
        }

        return result.isEmpty ? duration : result.joined(separator: " ")
    }

    /// Parse ISO 8601 duration to total seconds
    private func parseDurationToSeconds(_ duration: String) -> Int {
        guard !duration.isEmpty else { return 0 }

        var totalSeconds = 0
        var current = ""

        for char in duration {
            if char.isNumber {
                current += String(char)
            } else if char == "H", let hours = Int(current) {
                totalSeconds += hours * 3600
                current = ""
            } else if char == "M", let mins = Int(current) {
                totalSeconds += mins * 60
                current = ""
            } else if char == "S", let secs = Int(current) {
                totalSeconds += secs
                current = ""
            }
        }

        return totalSeconds
    }

    // MARK: - Response Parsing

    private func parseAnalysisResponse(response: String) throws -> Phase0Result {
        // Extract JSON from response
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw Phase0Error.invalidResponse("Could not find JSON in response")
        }

        let decoded = try JSONDecoder().decode(ExecutionTraceResponseData.self, from: data)

        // Build execution trace
        let opening = OpeningWindow(
            durationSeconds: decoded.opening.durationSeconds,
            whatHappens: decoded.opening.whatHappens,
            hookType: decoded.opening.hookType
        )

        let pivots = decoded.pivots.map { p in
            PivotMoment(
                pivotNumber: p.pivotNumber,
                timestampPercent: p.timestampPercent,
                triggerMoment: p.triggerMoment,
                assumptionChallenged: p.assumptionChallenged
            )
        }

        let executionTrace = ExecutionTrace(
            opening: opening,
            pivots: pivots,
            evidenceFlow: decoded.evidenceFlow,
            escalation: decoded.escalation,
            resolution: decoded.resolution,
            narratorRole: decoded.narratorRole
        )

        // Return Phase0Result with execution trace as primary data
        // Legacy categorical fields are set to defaults (execution trace is what matters)
        return Phase0Result(
            pivotCount: pivots.count,
            retentionStrategy: "",  // Legacy - not extracted
            argumentType: "",       // Legacy - not extracted
            sectionDensity: "",     // Legacy - not extracted
            transitionMarkers: [],  // Legacy - not extracted
            evidenceTypes: decoded.evidenceFlow,  // Use ordered evidence flow
            coreQuestion: "",       // Legacy - not extracted
            narrativeDevice: "",    // Legacy - not extracted
            majorTransitions: [],   // Legacy - not extracted
            reasoning: "",          // Legacy - not extracted
            analyzedAt: Date(),
            format: nil,            // Legacy - not extracted
            executionTrace: executionTrace
        )
    }

    // MARK: - JSON Extraction

    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in ```json block
        if let jsonBlockRange = response.range(of: "```json"),
           let endBlockRange = response.range(of: "```", range: jsonBlockRange.upperBound..<response.endIndex) {
            let jsonContent = String(response[jsonBlockRange.upperBound..<endBlockRange.lowerBound])
            return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON in generic ``` block
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            let content = String(response[startRange.upperBound..<endRange.lowerBound])
            if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try to find JSON by locating first { and last }
        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            let jsonContent = String(response[firstBrace...lastBrace])
            return jsonContent
        }

        // If already clean JSON
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }

        return nil
    }

    // MARK: - Response Data Types

    private struct ExecutionTraceResponseData: Codable {
        let opening: OpeningWindowData
        let pivots: [PivotMomentData]
        let evidenceFlow: [String]
        let escalation: String
        let resolution: String
        let narratorRole: String
    }

    private struct OpeningWindowData: Codable {
        let durationSeconds: Int
        let whatHappens: String
        let hookType: String
    }

    private struct PivotMomentData: Codable {
        let pivotNumber: Int
        let timestampPercent: Int
        let triggerMoment: String
        let assumptionChallenged: String
    }

    enum Phase0Error: Error, LocalizedError {
        case invalidResponse(String)
        case noTranscript

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message): return "Invalid Phase 0 response: \(message)"
            case .noTranscript: return "No transcript available for analysis"
            }
        }
    }
}
