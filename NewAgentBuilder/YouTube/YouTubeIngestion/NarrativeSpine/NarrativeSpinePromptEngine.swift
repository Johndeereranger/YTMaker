//
//  NarrativeSpinePromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

struct NarrativeSpinePromptEngine {

    // MARK: - Generate Prompt

    /// Builds the system and user prompts for narrative spine extraction.
    /// - Parameters:
    ///   - video: The video to extract the spine from (must have transcript)
    ///   - existingSpines: Previously extracted spines from the same creator (for corpus examples)
    /// - Returns: Tuple of (systemPrompt, userPrompt)
    static func generatePrompt(
        video: YouTubeVideo,
        existingSpines: [NarrativeSpine]? = nil
    ) -> (system: String, user: String) {

        let systemPrompt = "You are a narrative structure analyst. Extract the construction pattern of the video as valid JSON. Do not include any text outside the JSON object."

        let durationMinutes = Int(video.durationMinutes.rounded())

        // Build corpus examples section if available
        let corpusSection: String
        if let spines = existingSpines, !spines.isEmpty {
            let selected = Array(spines.suffix(5))
            let examples = selected.map { $0.renderedText }.joined(separator: "\n\n---\n\n")
            corpusSection = """

            ### CORPUS EXAMPLES (if available)

            Below are previously extracted spines from this same creator. Study them for recurring patterns — how this creator opens, escalates, pivots, proves, and closes. Your extraction should be consistent with these in format, grain, and level of abstraction. If you notice the creator repeating a structural move that appears in multiple examples below, note it in the Creator pattern note field.

            \(examples)

            """
        } else {
            corpusSection = ""
        }

        let userPrompt = """
        You are extracting the **narrative construction pattern** of a YouTube video. Your job is to document **how the creator built the argument**, move by move, so that the pattern could be applied to a completely different topic.

        The key test for every beat you write: **would this description help someone build a video about a totally different subject?** If the beat only makes sense for this specific video's topic, you've written a content summary, not a construction pattern.

        ### Video metadata
        - **Duration:** \(durationMinutes) minutes

        ---
        \(corpusSection)
        ---

        ### What a beat is (and is not)

        A beat is one **narrative construction move** — a deliberate structural choice the creator made to advance the argument.

        **A beat IS:**
        - A distinct move that changes the viewer's understanding, raises new tension, or resolves existing tension
        - Something that, if removed, would break the causal chain — the next beat would stop making sense
        - Describable as a transferable pattern: "Creator stacks evidence through first-person experience before making an abstract claim"

        **A beat is NOT:**
        - An individual scene, location, or event (those are content that fills a beat)
        - A repetition of the same structural move with different content (three examples of the same point = one beat, not three)
        - Texture, color, transitions, or supporting detail within a larger move

        **The critical test:** If three consecutive moments in the video all serve the same structural purpose (e.g., three failed attempts during a challenge, three pieces of evidence stacked to prove a claim, three locations visited to demonstrate range), they are ONE beat with multiple instances — not three separate beats. The beat is the move ("Creator stacks failures to build genuine tension"). The individual instances are content within that beat, listed in the content tag.

        **Structural contrasts:** If the creator uses a deliberate contrast — a specific failure immediately mirrored by a specific success of the same type, or a spectacle immediately deflected toward something mundane — that contrast is ONE beat. Note the contrast pattern in the beat description (e.g., "Creator punctuates an accelerating montage with a matched failure/success pair to prove the outcome is genuinely uncertain"). Do not split the two halves into separate beats.

        ### Beat count guidance

        The beat count reflects the number of **distinct narrative moves**, not the number of scenes or events.

        Rough calibration:
        - 5-10 min video: 4-8 beats
        - 10-15 min video: 7-12 beats
        - 15-25 min video: 10-18 beats
        - 25-40+ min video: 15-25 beats

        If your count exceeds the upper range, audit for beats that are really instances of the same move. If your count is below the lower range, check for compressed beats that contain multiple distinct moves.

        ### Beat format

        For each beat, the description follows this format:
        [One sentence describing THE MOVE the creator made] → [why this move appears here — what it sets up, proves, or resolves]

        **Grain guidance for the beat description:**

        Correct — transferable move with causal role:
        "Creator uses first-person physical immersion at the subject's most extreme scale to ground the viewer before any analysis → establishes experiential credibility and creates the visceral anchor that earns the viewer's patience for the explanation to come"

        Too content-specific:
        "Johnny rides through the longest tunnel in the world at 200km/h → shows how impressive Swiss trains are"

        Too abstract:
        "Creator introduces the topic → gets the viewer interested"

        **Do not add "technique:" labels, method descriptions, or restatements of the move inside the beat description.** The beat description IS the technique. One sentence describing the move, arrow, one sentence describing the causal role. Nothing else.

        ### Function labels

        - `opening-anchor` — grounds the viewer in a specific moment, place, or experience
        - `frame-set` — establishes the lens, perspective, or rules through which the story will be told
        - `setup-plant` — introduces an element that won't pay off until significantly later; the viewer may not notice it's important yet
        - `problem-statement` — names the core question or tension that drives the narrative
        - `stakes-raise` — quantifies, escalates, or makes the problem urgent
        - `context` — provides background necessary to understand what comes next
        - `expected-path` — shows the obvious approach, conventional wisdom, or first attempt
        - `dead-end` — a path that was tried and explicitly fails, showing what didn't work and creating a gap the viewer wants filled
        - `complication` — something doesn't add up, a contradiction surfaces, or a new obstacle appears
        - `method-shift` — a new approach, tool, lens, or framework is introduced
        - `discovery` — new information surfaces that changes understanding
        - `evidence` — data, example, anecdote, or proof that supports an adjacent beat
        - `reframe` — the problem or situation gets reinterpreted in light of new understanding
        - `mechanism` — explains HOW or WHY something works at a deeper level
        - `implication` — what this means going forward — the so-what
        - `escalation` — the scope expands beyond the original problem or the pressure increases
        - `pivot` — the story changes direction based on what was just established
        - `callback` — returns to an earlier beat with new meaning or payoff
        - `resolution` — the original question or tension gets answered

        ### Rules

        1. **Write moves, not summaries.** Every beat description must be transferable to a different topic. The content tag carries the video-specific details.

        2. **Every beat must earn its place.** If removing a beat doesn't break the causal chain, it's not a beat — it's content inside an adjacent beat. Merge it.

        3. **Consecutive instances of the same move are one beat.** Three examples proving the same claim = one evidence beat. Five obstacles in a challenge sequence that all serve "building tension through accumulated failure" = one escalation beat. List the instances in the content tag, not as separate beats.

        4. **Structural contrasts are one beat.** A deliberate failure/success pair, a spectacle/deflection pair, or any matched contrast the creator uses as a single rhetorical device = one beat. Describe the contrast pattern in the beat description. Do not split the two halves.

        5. **Dependencies are mandatory.** Every beat after Beat 1 must declare what it depends on. This is how the causal chain is enforced downstream — content from beat 8 cannot appear in any section that precedes the beats it depends on.

        6. **Do not invent content.** Every beat must trace to the transcript via the content tag.

        7. **Creator pattern notes are rare and specific.** Only flag moves that feel like a signature — something this creator does deliberately and distinctively, not a generic narrative technique. "Creator opens with physical immersion rather than stating a thesis" is a signature. "Creator uses evidence to support claims" is not. If you're adding pattern notes to more than a third of beats, you're being too generous.

        8. **Do not restate the move in different words.** No "technique:" labels, no method descriptions, no secondary explanations of what the beat is doing. The beat description speaks once. The content tag grounds it. That's it.

        ---

        ### After the beats, also produce:

        **THROUGHLINE**: One paragraph (3-5 sentences) tracing the causal chain through each phase of the video. This is not a summary of the topic — it is a summary of the structural logic.

        **PHASE STRUCTURE**: Name the distinct phases (2-5) and where transitions fall. For each phase, state the defining technique — not what content it covers.

        **STRUCTURAL SIGNATURES**: 3-7 observations about construction patterns that might recur across this creator's work. Each with a short reusable label name and a 1-2 sentence description with beat reference evidence.

        ---

        ### OUTPUT FORMAT

        Return your response as valid JSON with this exact structure:
        ```json
        {
          "beats": [
            {
              "beatNumber": 1,
              "beatSentence": "Creator does X → this sets up Y",
              "function": "opening-anchor",
              "contentTag": "specific content from this video",
              "dependsOn": [],
              "creatorPatternNote": null
            }
          ],
          "throughline": "One paragraph tracing the structural logic...",
          "phases": [
            {
              "phaseNumber": 1,
              "beatRange": [1, 5],
              "name": "Phase name",
              "definingTechnique": "What technique defines this phase"
            }
          ],
          "structuralSignatures": [
            {
              "name": "Pattern-name",
              "description": "1-2 sentence description. In this video: beat reference as evidence."
            }
          ]
        }
        ```

        IMPORTANT: Return ONLY the JSON object. No markdown fences, no preamble, no commentary.

        ---

        ## Transcript

        \(video.transcript ?? "")
        """

        return (system: systemPrompt, user: userPrompt)
    }

    // MARK: - Parse Response

    /// Parses the LLM JSON response into a NarrativeSpine
    static func parseResponse(_ text: String, video: YouTubeVideo) throws -> NarrativeSpine {
        // 1. Clean up response
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // Left smart quote
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // Right smart quote
            .replacingOccurrences(of: "\u{2018}", with: "'")   // Left single smart quote
            .replacingOccurrences(of: "\u{2019}", with: "'")   // Right single smart quote
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Try to extract JSON if wrapped in other text
        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NarrativeSpineError.parseFailed("Could not convert response to UTF-8 data")
        }

        // 3. Debug pass — log root keys
        if let generic = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            let keys = generic.keys.sorted().joined(separator: ", ")
            let beatCount = (generic["beats"] as? [[String: Any]])?.count ?? 0
            print("📋 Narrative spine JSON keys: [\(keys)], beats: \(beatCount)")
        }

        // 4. Decode to typed response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response: NarrativeSpineRawResponse
        do {
            response = try decoder.decode(NarrativeSpineRawResponse.self, from: jsonData)
        } catch {
            // WHAT: Decode to NarrativeSpineRawResponse failed
            // WHAT (raw data): Full JSON the LLM returned
            print("❌ SPINE JSON PARSE FAILURE — Full raw JSON below:")
            print("─── BEGIN RAW JSON ───")
            print(cleaned)
            print("─── END RAW JSON ───")

            // WHY: Extract specific DecodingError details
            let detail: String
            if let decodingError = error as? DecodingError {
                let path: String
                switch decodingError {
                case .typeMismatch(let type, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Type mismatch at '\(path)': expected \(type), debug: \(ctx.debugDescription)"
                case .keyNotFound(let key, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Missing key '\(key.stringValue)' at '\(path)': \(ctx.debugDescription)"
                case .valueNotFound(let type, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Null value for non-optional \(type) at '\(path)': \(ctx.debugDescription)"
                case .dataCorrupted(let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Data corrupted at '\(path)': \(ctx.debugDescription)"
                @unknown default:
                    detail = "Unknown DecodingError: \(error)"
                }
                print("❌ DecodingError detail: \(detail)")
            } else {
                detail = "\(error)"
                print("❌ Non-DecodingError: \(detail)")
            }

            // Per-field isolation: try each top-level field independently
            print("─── PER-FIELD DECODE ISOLATION ───")
            let fieldsOk: [String: Bool] = [
                "beats": (try? decoder.decode(SpineDiag.BeatsOnly.self, from: jsonData)) != nil,
                "throughline": (try? decoder.decode(SpineDiag.ThroughlineOnly.self, from: jsonData)) != nil,
                "phases": (try? decoder.decode(SpineDiag.PhasesOnly.self, from: jsonData)) != nil,
                "structuralSignatures": (try? decoder.decode(SpineDiag.SignaturesOnly.self, from: jsonData)) != nil
            ]
            for (field, ok) in fieldsOk.sorted(by: { $0.key < $1.key }) {
                print("  \(ok ? "✅" : "❌") \(field)")
            }

            // If beats failed, try each beat individually
            if fieldsOk["beats"] != true,
               let generic = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let beatsArray = generic["beats"] as? [[String: Any]] {
                print("─── PER-BEAT ISOLATION (\(beatsArray.count) beats) ───")
                for (idx, beatDict) in beatsArray.enumerated() {
                    do {
                        let beatData = try JSONSerialization.data(withJSONObject: beatDict)
                        _ = try decoder.decode(RawBeat.self, from: beatData)
                        print("  ✅ Beat \(idx + 1)")
                    } catch {
                        print("  ❌ Beat \(idx + 1): \(error)")
                        print("     Raw keys: \(beatDict.keys.sorted().joined(separator: ", "))")
                        for (k, v) in beatDict.sorted(by: { $0.key < $1.key }) {
                            print("     \(k): \(type(of: v)) = \(v)")
                        }
                    }
                }
            }

            // If phases failed, try each phase individually
            if fieldsOk["phases"] != true,
               let generic = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let phasesArray = generic["phases"] as? [[String: Any]] {
                print("─── PER-PHASE ISOLATION (\(phasesArray.count) phases) ───")
                for (idx, phaseDict) in phasesArray.enumerated() {
                    do {
                        let phaseData = try JSONSerialization.data(withJSONObject: phaseDict)
                        _ = try decoder.decode(RawPhase.self, from: phaseData)
                        print("  ✅ Phase \(idx + 1)")
                    } catch {
                        print("  ❌ Phase \(idx + 1): \(error)")
                        print("     Raw keys: \(phaseDict.keys.sorted().joined(separator: ", "))")
                    }
                }
            }

            print("─── END DIAGNOSTIC ───")
            throw NarrativeSpineError.parseFailed("JSON decode failed: \(detail)")
        }

        // 5. Validate function labels
        for beat in response.beats {
            if !NarrativeSpineBeat.isKnownFunction(beat.function) {
                print("⚠️ Unknown function label '\(beat.function)' on Beat \(beat.beatNumber) — not in 19-label taxonomy")
            }
        }

        // 6. Construct NarrativeSpine
        let beats = response.beats.map { raw in
            NarrativeSpineBeat(
                beatNumber: raw.beatNumber,
                beatSentence: raw.beatSentence,
                function: raw.function,
                contentTag: raw.contentTag,
                dependsOn: raw.dependsOn,
                creatorPatternNote: raw.creatorPatternNote
            )
        }

        let phases = response.phases.map { raw in
            NarrativeSpinePhase(
                phaseNumber: raw.phaseNumber,
                beatRange: raw.beatRange,
                name: raw.name,
                definingTechnique: raw.definingTechnique
            )
        }

        let signatures = response.structuralSignatures.map { raw in
            NarrativeSpineSignature(
                name: raw.name,
                description: raw.description
            )
        }

        // 7. Build rendered text programmatically
        let renderedText = NarrativeSpine.renderText(
            beats: beats,
            throughline: response.throughline,
            phases: phases,
            structuralSignatures: signatures
        )

        let spine = NarrativeSpine(
            videoId: video.videoId,
            channelId: video.channelId,
            duration: video.durationMinutes,
            extractedAt: Date(),
            beats: beats,
            throughline: response.throughline,
            phases: phases,
            structuralSignatures: signatures,
            renderedText: renderedText
        )

        print("✅ Parsed narrative spine: \(beats.count) beats, \(phases.count) phases, \(signatures.count) signatures")
        return spine
    }
}

// MARK: - Raw Response Types (intermediate decode targets)

private struct NarrativeSpineRawResponse: Codable {
    let beats: [RawBeat]
    let throughline: String
    let phases: [RawPhase]
    let structuralSignatures: [RawSignature]
}

private struct RawBeat: Codable {
    let beatNumber: Int
    let beatSentence: String
    let function: String
    let contentTag: String
    let dependsOn: [Int]
    let creatorPatternNote: String?
}

private struct RawPhase: Codable {
    let phaseNumber: Int
    let beatRange: [Int]
    let name: String
    let definingTechnique: String
}

private struct RawSignature: Codable {
    let name: String
    let description: String
}

// MARK: - Diagnostic Isolation Types (for per-field decode testing)

private enum SpineDiag {
    struct BeatsOnly: Codable { let beats: [RawBeat] }
    struct ThroughlineOnly: Codable { let throughline: String }
    struct PhasesOnly: Codable { let phases: [RawPhase] }
    struct SignaturesOnly: Codable { let structuralSignatures: [RawSignature] }
}

// MARK: - Error Types

enum NarrativeSpineError: LocalizedError {
    case missingTranscript
    case missingData(String)
    case parseFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingTranscript: return "Video has no transcript"
        case .missingData(let detail): return "Missing data: \(detail)"
        case .parseFailed(let detail): return "Parse failed: \(detail)"
        case .apiError(let detail): return "API error: \(detail)"
        }
    }
}
