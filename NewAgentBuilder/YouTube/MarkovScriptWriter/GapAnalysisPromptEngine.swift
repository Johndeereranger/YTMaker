//
//  GapAnalysisPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/31/26.
//
//  Prompt construction for the 5 gap analysis paths.
//  All paths output the same GapFinding format.
//

import Foundation

struct GapAnalysisPromptEngine {

    // MARK: - Shared Components

    static let gapSystemPrompt = "You are a narrative gap analyst. Your job is to identify structural weaknesses, missing causal links, and content gaps in narrative spines. Return valid JSON only. No markdown fences, no preamble, no commentary."

    static let gapTypeDefinitions = """
    ### Gap Types

    - `structural` — A beat is in an unusual position for its function, the phase architecture is malformed, or a beat type that should be present is missing entirely.
    - `causal` — A beat claims to follow from a previous beat, but the causal link is weak, missing, or logically unsupported. The viewer would need to infer a step the spine skips.
    - `content-density` — A beat has too little content to fill its structural role (sparse), or too much content crammed into one beat that should be split (overloaded).
    - `viewer-state` — At this point in the spine, the viewer's mental model is incomplete, confused, or misaligned. The viewer doesn't have what they need to follow the next move.
    - `payoff` — A setup (setup-plant, problem-statement, stakes-raise) is never resolved, or a resolution/callback appears without adequate prior setup.
    - `creator-signature` — A structural pattern this creator almost always uses is absent. The spine doesn't feel like this creator's work.
    """

    static let gapActionDefinitions = """
    ### Action Types

    - `RESHAPE` — The content exists in the rambling but needs to be restructured, reordered, or reframed within the spine.
    - `SURFACE` — The content is implied or partially present but needs to be made explicit — the creator touched on it but didn't develop it.
    - `CONTENT_GAP` — The spine needs content the rambling doesn't contain. The creator needs to record new material or answer a specific question.
    """

    static let gapGuardrails = """
    ### Guardrails

    - Do NOT suggest gaps that require the creator to do new research. Only flag gaps the creator can fill from their existing knowledge.
    - Do NOT suggest tone, style, or delivery improvements. Focus on structural and content gaps only.
    - Do NOT flag a gap just because the spine is short or simple. A 6-beat spine for a simple topic is fine.
    - Every questionToRambler must be specific and answerable. "Tell me more about X" is NOT acceptable. "What happened when you tried the trail camera at the south food plot — did the deer show up or not?" IS acceptable.
    """

    // ┌──────────────────────────────────────────────────────────────┐
    // │  SUPPRESSED GAP PATTERNS                                     │
    // │                                                               │
    // │  Add new suppression rules here when the gap analysis         │
    // │  repeatedly generates a bad question pattern.                 │
    // │  Each rule should be specific to a recurring AI mistake.      │
    // │  Keep rules concrete — not philosophical generalizations.     │
    // │                                                               │
    // │  HOW TO ADD A NEW RULE:                                       │
    // │  1. Add a new "- Do not..." bullet to the string below        │
    // │  2. All 6 gap paths (G1-G6) pick it up automatically          │
    // └──────────────────────────────────────────────────────────────┘
    static let suppressedGapPatterns = """
    ### Suppressed Gap Patterns

    The following question patterns are BANNED. Do not generate gap findings
    whose questionToRambler matches any of these patterns:

    - Do not ask the creator to describe what thermal drone imagery looks like, how thermal imaging displays animals, or how to visually interpret thermal footage. The viewer can see the thermal footage directly.
    """

    static let gapCapInstruction = """
    ### Finding Limits

    Produce no more than 3 HIGH, 3 MEDIUM, and 2 LOW priority findings. Prioritize during generation — if you identify more gaps than the cap allows, include only the most impactful ones. Do not produce findings just to fill the cap.
    """

    static let gapOutputFormat = """
    ### OUTPUT FORMAT

    Return your response as a JSON array of gap findings:
    ```json
    [
      {
        "type": "structural",
        "action": "RESHAPE",
        "location": "Between beats 4 and 5",
        "whatsMissing": "A method-shift beat that transitions from the failed expected-path to the new approach",
        "whyItMatters": "Without this transition, the viewer doesn't understand why the creator abandoned the first approach",
        "questionToRambler": "When the first approach with the food plots failed, what specifically made you realize you needed a completely different strategy?",
        "priority": "HIGH"
      }
    ]
    ```

    IMPORTANT: Return ONLY the JSON array. No markdown fences, no preamble, no commentary.
    """

    // MARK: - G1: Single LLM Gap Detection

    static func g1SingleGapDetection(
        spine: NarrativeSpine,
        profile: CreatorNarrativeProfile,
        contentInventory: String?
    ) -> (system: String, user: String) {
        var userParts: [String] = []

        userParts.append("Analyze the narrative spine below for gaps, weaknesses, and missing elements. Evaluate all 6 gap types.")
        userParts.append("")
        userParts.append(ArcComparisonPromptEngine.renderProfile(profile))
        userParts.append("")
        userParts.append(ArcComparisonPromptEngine.functionTaxonomy)
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)

        if let inventory = contentInventory {
            userParts.append("")
            userParts.append("### Content Inventory")
            userParts.append("Use this to evaluate content-density gaps — which beats have too little or too much content.")
            userParts.append("")
            userParts.append(inventory)
        } else {
            userParts.append("")
            userParts.append("No content inventory is available. Skip content-density gap detection.")
        }

        userParts.append("")
        userParts.append(gapOutputFormat)
        userParts.append("")
        userParts.append("---")
        userParts.append("")
        userParts.append("## Narrative Spine")
        userParts.append("")
        userParts.append(spine.renderedText)

        return (system: gapSystemPrompt, user: userParts.joined(separator: "\n"))
    }

    // MARK: - G2: LLM with Programmatic Flags

    static func g2LLMWithFlags(
        spine: NarrativeSpine,
        contentInventory: String?,
        programmaticFlags: ProgrammaticGapFlags
    ) -> (system: String, user: String) {
        var userParts: [String] = []

        userParts.append("A programmatic pre-analysis has already flagged potential structural issues in the narrative spine below. Your job is to:")
        userParts.append("1. Review each programmatic flag — confirm, dismiss, or refine it into a proper gap finding.")
        userParts.append("2. Add any causal or viewer-state gaps the programmatic pass cannot detect.")
        userParts.append("")
        userParts.append("### Programmatic Flags")
        userParts.append("")
        userParts.append(programmaticFlags.renderedSummary)
        userParts.append("")
        userParts.append(ArcComparisonPromptEngine.functionTaxonomy)
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)

        if let inventory = contentInventory {
            userParts.append("")
            userParts.append("### Content Inventory")
            userParts.append("")
            userParts.append(inventory)
        }

        userParts.append("")
        userParts.append(gapOutputFormat)
        userParts.append("")
        userParts.append("---")
        userParts.append("")
        userParts.append("## Narrative Spine")
        userParts.append("")
        userParts.append(spine.renderedText)

        return (system: gapSystemPrompt, user: userParts.joined(separator: "\n"))
    }

    // MARK: - G3: Representative Comparison

    static func g3RepresentativeComparison(
        spine: NarrativeSpine,
        representativeSpines: [NarrativeSpine],
        contentInventory: String?
    ) -> (system: String, user: String) {
        var userParts: [String] = []

        userParts.append("Compare the candidate spine below against the creator's representative spines. Identify where the candidate deviates from the creator's established patterns in ways that weaken the narrative.")
        userParts.append("")
        userParts.append("### Representative Spines (\(representativeSpines.count) examples)")
        userParts.append("")
        userParts.append("These are the creator's most characteristic narrative structures. The candidate spine should be consistent with their patterns unless there's a good reason to deviate.")
        userParts.append("")
        for (i, repSpine) in representativeSpines.enumerated() {
            userParts.append("--- Example \(i + 1) ---")
            userParts.append(repSpine.renderedText)
            userParts.append("")
        }

        userParts.append(ArcComparisonPromptEngine.functionTaxonomy)
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)
        userParts.append("")
        userParts.append("Focus on: structural deviations, missing creator-signature patterns, and phase architecture differences. A deviation is only a gap if it weakens the narrative — not every difference is a problem.")

        if let inventory = contentInventory {
            userParts.append("")
            userParts.append("### Content Inventory")
            userParts.append("")
            userParts.append(inventory)
        }

        userParts.append("")
        userParts.append(gapOutputFormat)
        userParts.append("")
        userParts.append("---")
        userParts.append("")
        userParts.append("## Candidate Spine")
        userParts.append("")
        userParts.append(spine.renderedText)

        return (system: gapSystemPrompt, user: userParts.joined(separator: "\n"))
    }

    // MARK: - G4: Viewer Simulation

    static func g4ViewerSimulation(
        spine: NarrativeSpine
    ) -> (system: String, user: String) {
        let system = "You are a first-time viewer. You know nothing about this creator, their style, or their topic. Read the narrative spine below as if you're encountering this story for the first time. Report every point where you're confused, where the logic jumps, or where you'd lose interest."

        var userParts: [String] = []

        userParts.append("Read the narrative spine below as a viewer encountering it for the first time. You have NO context about the creator, their audience, or their previous content.")
        userParts.append("")
        userParts.append("For each gap you find, ask yourself:")
        userParts.append("- Am I confused about what just happened? (viewer-state)")
        userParts.append("- Did the argument just skip a step? (causal)")
        userParts.append("- Was something set up that never paid off? (payoff)")
        userParts.append("- Does this beat feel empty or overloaded? (content-density)")
        userParts.append("- Is the structure doing something weird here? (structural)")
        userParts.append("")
        userParts.append("Do NOT consider creator-signature gaps — you don't know this creator.")
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)
        userParts.append("")
        userParts.append(gapOutputFormat)
        userParts.append("")
        userParts.append("---")
        userParts.append("")
        userParts.append("## Narrative Spine")
        userParts.append("")
        userParts.append(spine.renderedText)

        return (system: system, user: userParts.joined(separator: "\n"))
    }

    // MARK: - G5: Merge & Dedup

    static func g5MergeDedup(
        viewerFindings: [GapFinding],
        profileFindings: [GapFinding]
    ) -> (system: String, user: String) {
        let system = "You are a gap analysis integrator. You receive gap findings from two independent analysis paths and merge them into a single deduplicated list."

        var userParts: [String] = []

        userParts.append("Two independent gap analyses were run on the same narrative spine:")
        userParts.append("1. **Viewer Simulation** (G4) — a first-time viewer with no creator context")
        userParts.append("2. **Profile Gap Detection** (G1) — an analyst with full creator profile and corpus knowledge")
        userParts.append("")
        userParts.append("Your job:")
        userParts.append("1. If both inputs identify the same structural location AND the same type of gap, merge them into ONE finding. Use the more specific questionToRambler. Elevate priority if both paths flagged it independently (e.g., MEDIUM from both → HIGH).")
        userParts.append("2. Keep unique findings from each path as-is.")
        userParts.append("3. Apply the cap: no more than 3 HIGH, 3 MEDIUM, 2 LOW.")
        userParts.append("4. If a gap was found by both paths, note this in whyItMatters (e.g., \"Flagged by both viewer simulation and profile analysis\").")
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)
        userParts.append("")
        userParts.append("### Viewer Simulation Findings (G4)")
        userParts.append("")
        userParts.append(renderFindingsForPrompt(viewerFindings))
        userParts.append("")
        userParts.append("### Profile Gap Detection Findings (G1)")
        userParts.append("")
        userParts.append(renderFindingsForPrompt(profileFindings))
        userParts.append("")
        userParts.append(gapOutputFormat)

        return (system: system, user: userParts.joined(separator: "\n"))
    }

    // MARK: - G6: Synthesis (all completed paths → one merged set)

    static func g6Synthesis(
        pathResults: [(path: GapPath, findings: [GapFinding])]
    ) -> (system: String, user: String) {
        let system = "You are a gap analysis synthesizer. You receive gap findings from multiple independent analysis approaches run on the same narrative spine. Produce one authoritative, deduplicated finding set that is richer and better-phrased than any individual input."

        var userParts: [String] = []

        userParts.append("Multiple independent gap analyses were run on the same narrative spine. Each used a different methodology:")
        userParts.append("")

        for (path, findings) in pathResults {
            userParts.append("### \(path.rawValue): \(path.displayName)")
            userParts.append("*Approach: \(path.shortDescription)*")
            userParts.append("")
            userParts.append(renderFindingsForPrompt(findings))
            userParts.append("")
        }

        userParts.append("---")
        userParts.append("")
        userParts.append("Your job: Produce ONE authoritative finding set by synthesizing all the above.")
        userParts.append("")
        userParts.append("Rules:")
        userParts.append("1. If multiple paths flag the same structural location AND the same gap type, merge into ONE finding. Use the most specific questionToRambler. Note in whyItMatters how many paths independently flagged it (e.g., \"Identified by G1, G3, and G4\").")
        userParts.append("2. If a gap was found by 3+ paths, it is almost certainly HIGH priority regardless of individual ratings.")
        userParts.append("3. If only one path found a gap, keep it but don't automatically elevate — it may be path-specific noise.")
        userParts.append("4. Rephrase findings for clarity when merging — the goal is one clean set, not a collage of quotes from different paths.")
        userParts.append("5. The questionToRambler should be the most specific, actionable version from any source path.")
        userParts.append("")
        userParts.append(gapTypeDefinitions)
        userParts.append(gapActionDefinitions)
        userParts.append(gapGuardrails)
        userParts.append(suppressedGapPatterns)
        userParts.append(gapCapInstruction)
        userParts.append("")
        userParts.append(gapOutputFormat)

        return (system: system, user: userParts.joined(separator: "\n"))
    }

    // MARK: - Refinement Pass (cross-reference findings against raw rambling)

    static func refinementPass(
        findings: [GapFinding],
        rawRambling: String
    ) -> (system: String, user: String) {
        let system = "You are a gap finding quality reviewer. You cross-reference gap findings against the creator's raw rambling transcript to determine if each gap is already answered, partially answered, or genuinely missing. Return valid JSON only. No markdown fences, no preamble, no commentary."

        var userParts: [String] = []

        userParts.append("Below are gap findings identified in a narrative spine, followed by the creator's raw rambling transcript that the spine was built from.")
        userParts.append("")
        userParts.append("For EACH finding, cross-reference it against the raw rambling and classify it:")
        userParts.append("")
        userParts.append("**resolved** — The rambling clearly answers this gap. The content exists but the spine builder didn't pick it up. Quote the relevant section (2-3 sentences max). Explain what should be incorporated into the spine.")
        userParts.append("")
        userParts.append("**refined** — The rambling partially addresses this but doesn't fully cover it. Quote what's already there. Write a NEW, sharper question that targets ONLY what's actually missing — do not repeat what the creator already said. The refined question should acknowledge what they already covered.")
        userParts.append("")
        userParts.append("**confirmed** — The rambling doesn't address this at all. The original question stands as-is.")
        userParts.append("")
        userParts.append(suppressedGapPatterns)
        userParts.append("")
        userParts.append("### OUTPUT FORMAT")
        userParts.append("")
        userParts.append("Return a JSON array with one entry per finding, matched by index:")
        userParts.append("```json")
        userParts.append("[")
        userParts.append("  {")
        userParts.append("    \"findingIndex\": 0,")
        userParts.append("    \"status\": \"resolved\",")
        userParts.append("    \"ramblingExcerpt\": \"I flew the thermal drone over the south field and the deer were bedded down right where I expected...\",")
        userParts.append("    \"refinedQuestion\": null,")
        userParts.append("    \"note\": \"The creator describes this exact scenario in their rambling. The spine builder should incorporate this.\"")
        userParts.append("  },")
        userParts.append("  {")
        userParts.append("    \"findingIndex\": 1,")
        userParts.append("    \"status\": \"refined\",")
        userParts.append("    \"ramblingExcerpt\": \"The bucks were bedded down near the creek...\",")
        userParts.append("    \"refinedQuestion\": \"You mentioned bucks bedding near the creek — did you see them arrive or were they already there when the drone went up? That arrival moment would strengthen the discovery beat.\",")
        userParts.append("    \"note\": \"Creator mentions the location but not the timing or how they found them.\"")
        userParts.append("  },")
        userParts.append("  {")
        userParts.append("    \"findingIndex\": 2,")
        userParts.append("    \"status\": \"confirmed\",")
        userParts.append("    \"ramblingExcerpt\": null,")
        userParts.append("    \"refinedQuestion\": null,")
        userParts.append("    \"note\": \"The rambling doesn't touch on this topic at all.\"")
        userParts.append("  }")
        userParts.append("]")
        userParts.append("```")
        userParts.append("")
        userParts.append("IMPORTANT: Return ONLY the JSON array. No markdown fences, no preamble, no commentary.")
        userParts.append("")
        userParts.append("---")
        userParts.append("")
        userParts.append("### Gap Findings to Review (\(findings.count) findings)")
        userParts.append("")
        for (i, f) in findings.enumerated() {
            userParts.append("\(i). [\(f.priority.rawValue)] [\(f.type.rawValue)] [\(f.action.rawValue)]")
            userParts.append("   Location: \(f.location)")
            userParts.append("   Missing: \(f.whatsMissing)")
            userParts.append("   Why: \(f.whyItMatters)")
            userParts.append("   Question: \(f.questionToRambler)")
            userParts.append("")
        }

        userParts.append("---")
        userParts.append("")
        userParts.append("### Raw Rambling Transcript")
        userParts.append("")
        userParts.append(rawRambling)

        return (system: system, user: userParts.joined(separator: "\n"))
    }

    // MARK: - Refinement Parsing

    static func parseRefinementResults(from text: String, into findings: [GapFinding]) -> [GapFinding] {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "["),
           let endIdx = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let data = cleaned.data(using: .utf8),
              let dicts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return findings }

        var refined = findings
        for dict in dicts {
            guard let index = dict["findingIndex"] as? Int,
                  index >= 0, index < refined.count,
                  let statusStr = dict["status"] as? String,
                  let status = RefinementStatus(rawValue: statusStr)
            else { continue }

            refined[index].refinementStatus = status
            refined[index].ramblingExcerpt = dict["ramblingExcerpt"] as? String
            refined[index].refinedQuestion = dict["refinedQuestion"] as? String
            refined[index].refinementNote = dict["note"] as? String
        }

        return refined
    }

    // MARK: - Helpers

    private static func renderFindingsForPrompt(_ findings: [GapFinding]) -> String {
        if findings.isEmpty { return "(No findings)" }
        var lines: [String] = []
        for (i, f) in findings.enumerated() {
            lines.append("\(i + 1). [\(f.priority.rawValue)] [\(f.type.rawValue)] [\(f.action.rawValue)]")
            lines.append("   Location: \(f.location)")
            lines.append("   Missing: \(f.whatsMissing)")
            lines.append("   Why: \(f.whyItMatters)")
            lines.append("   Question: \(f.questionToRambler)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parseGapFindings(from text: String) -> [GapFinding] {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON array boundaries
        if let startIdx = cleaned.firstIndex(of: "["),
           let endIdx = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let data = cleaned.data(using: .utf8) else { return [] }

        // Try structured decode first
        if let rawFindings = try? JSONDecoder().decode([RawGapFinding].self, from: data) {
            return rawFindings.compactMap { $0.toGapFinding() }
        }

        // Fallback: try decoding as array of dictionaries
        if let dicts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return dicts.compactMap { dict -> GapFinding? in
                guard let typeStr = dict["type"] as? String,
                      let type = GapType(rawValue: typeStr),
                      let actionStr = dict["action"] as? String,
                      let action = GapAction(rawValue: actionStr),
                      let location = dict["location"] as? String,
                      let whatsMissing = dict["whatsMissing"] as? String,
                      let whyItMatters = dict["whyItMatters"] as? String,
                      let question = dict["questionToRambler"] as? String,
                      let priorityStr = dict["priority"] as? String,
                      let priority = GapPriority(rawValue: priorityStr)
                else { return nil }

                return GapFinding(
                    type: type, action: action, location: location,
                    whatsMissing: whatsMissing, whyItMatters: whyItMatters,
                    questionToRambler: question, priority: priority
                )
            }
        }

        return []
    }

    /// Code-level backstop: enforce 3 HIGH / 3 MEDIUM / 2 LOW cap.
    static func enforceCapLimit(_ findings: [GapFinding]) -> [GapFinding] {
        let sorted = findings.sorted { $0.priority < $1.priority }
        var result: [GapFinding] = []
        var highCount = 0
        var mediumCount = 0
        var lowCount = 0

        for finding in sorted {
            switch finding.priority {
            case .high:
                if highCount < 3 { result.append(finding); highCount += 1 }
            case .medium:
                if mediumCount < 3 { result.append(finding); mediumCount += 1 }
            case .low:
                if lowCount < 2 { result.append(finding); lowCount += 1 }
            }
        }
        return result
    }
}

// MARK: - Raw Parsing Type

private struct RawGapFinding: Codable {
    let type: String
    let action: String
    let location: String
    let whatsMissing: String
    let whyItMatters: String
    let questionToRambler: String
    let priority: String

    func toGapFinding() -> GapFinding? {
        guard let gapType = GapType(rawValue: type),
              let gapAction = GapAction(rawValue: action),
              let gapPriority = GapPriority(rawValue: priority)
        else { return nil }

        return GapFinding(
            type: gapType, action: gapAction, location: location,
            whatsMissing: whatsMissing, whyItMatters: whyItMatters,
            questionToRambler: questionToRambler, priority: gapPriority
        )
    }
}
