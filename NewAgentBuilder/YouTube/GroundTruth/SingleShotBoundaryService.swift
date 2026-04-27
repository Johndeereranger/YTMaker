//
//  SingleShotBoundaryService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/27/26.
//

import Foundation

// MARK: - Single Shot Result

struct SingleShotResult {
    let perRunBoundaries: [Set<Int>]        // each run's 0-indexed gap indices
    let consensusBoundaries: Set<Int>       // 2/3+ agreement
    let unanimousBoundaries: Set<Int>       // 3/3 agreement
    let debugOutput: String
    let runDuration: TimeInterval
}

// MARK: - Single Shot Boundary Service

class SingleShotBoundaryService {

    static let shared = SingleShotBoundaryService()
    private init() {}

    /// Run 3 parallel LLM calls, return internal 2/3+ consensus boundaries.
    /// Returns 0-indexed gap indices (gap after sentence i).
    func detectBoundaries(
        sentences: [String],
        temperature: Double = 0.3,
        runCount: Int = 3
    ) async -> SingleShotResult {
        let startTime = Date()
        let numberedTranscript = buildNumberedTranscript(sentences)
        let prompt = buildPrompt(numberedTranscript: numberedTranscript)

        // Run in parallel
        let perRunBoundaries: [Set<Int>] = await withTaskGroup(of: (Int, Set<Int>).self) { group in
            for runIndex in 0..<runCount {
                group.addTask {
                    let boundaries = await self.executeSingleRun(
                        prompt: prompt,
                        sentenceCount: sentences.count,
                        temperature: temperature,
                        runIndex: runIndex
                    )
                    return (runIndex, boundaries)
                }
            }

            var results = Array(repeating: Set<Int>(), count: runCount)
            for await (index, boundaries) in group {
                results[index] = boundaries
            }
            return results
        }

        // Compute consensus
        let allGapIndices = perRunBoundaries.reduce(into: Set<Int>()) { $0.formUnion($1) }
        var consensusBoundaries = Set<Int>()
        var unanimousBoundaries = Set<Int>()

        for gapIndex in allGapIndices {
            let votes = perRunBoundaries.filter { $0.contains(gapIndex) }.count
            if votes >= 2 {
                consensusBoundaries.insert(gapIndex)
            }
            if votes == runCount {
                unanimousBoundaries.insert(gapIndex)
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        // Build debug
        var debug = "SingleShot: \(runCount) runs @ temp \(temperature)\n"
        for (i, run) in perRunBoundaries.enumerated() {
            debug += "  Run \(i + 1): \(run.sorted()) (\(run.count) boundaries)\n"
        }
        debug += "  Consensus (2/\(runCount)+): \(consensusBoundaries.sorted()) (\(consensusBoundaries.count))\n"
        debug += "  Unanimous (\(runCount)/\(runCount)): \(unanimousBoundaries.sorted()) (\(unanimousBoundaries.count))\n"

        return SingleShotResult(
            perRunBoundaries: perRunBoundaries,
            consensusBoundaries: consensusBoundaries,
            unanimousBoundaries: unanimousBoundaries,
            debugOutput: debug,
            runDuration: duration
        )
    }

    // MARK: - Private

    private func executeSingleRun(
        prompt: String,
        sentenceCount: Int,
        temperature: Double,
        runIndex: Int
    ) async -> Set<Int> {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let params: [String: Any] = [
            "temperature": temperature,
            "max_tokens": 4000
        ]

        guard let response = await adapter.generate_response_bundle(
            prompt: prompt,
            promptBackgroundInfo: "",
            params: params
        ) else {
            print("⚠️ SingleShot run \(runIndex + 1) returned nil")
            return []
        }

        return parseResponse(response.content, sentenceCount: sentenceCount)
    }

    private func buildNumberedTranscript(_ sentences: [String]) -> String {
        sentences.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
    }

    private func buildPrompt(numberedTranscript: String) -> String {
        """
        You are analyzing a video transcript to identify section boundaries.

        A section boundary occurs where the speaker's rhetorical PURPOSE changes:
        - Shifts from narration to analysis or commentary
        - Moves from setup/context to action/execution
        - Pivots from one argument to a different argument
        - Transitions from evidence to conclusion
        - Changes from describing one topic/event to a different topic/event
        - Shifts from building tension to revealing the answer

        For each boundary, output exactly:
        BOUNDARY AFTER [N]: one-line reason

        Where N is the index of the LAST sentence before the shift.
        BOUNDARY AFTER [N] means sentence N is the LAST sentence of the outgoing section.
        Sentence N+1 is the FIRST sentence of the new section.

        Examples:
        - If sentence [12] is "Anyway, back to the main story." → BOUNDARY AFTER [12]
          (sentence 12 closes the aside, sentence 13 starts the new section)
        - If sentence [45] ends the setup and sentence [46] starts the evidence → BOUNDARY AFTER [45]

        TRANSCRIPT:
        \(numberedTranscript)
        """
    }

    /// Parse LLM response, converting 1-indexed sentence numbers to 0-indexed gap indices.
    /// "BOUNDARY AFTER [N]" → gap index N-1 (gap after 0-indexed sentence N-1)
    private func parseResponse(_ text: String, sentenceCount: Int) -> Set<Int> {
        let pattern = #"BOUNDARY\s+AFTER\s+\[?(\d+)\]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        var boundaries = Set<Int>()
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            if let range = Range(match.range(at: 1), in: text),
               let oneIndexed = Int(text[range]) {
                // Convert 1-indexed to 0-indexed gap
                let gapIndex = oneIndexed - 1
                if gapIndex >= 0 && gapIndex < sentenceCount - 1 {
                    boundaries.insert(gapIndex)
                }
            }
        }

        return boundaries
    }
}
