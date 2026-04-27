//
//  RamblingToGistService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/29/26.
//

import Foundation

/// Result from extraction including metadata for fidelity testing
struct ExtractionResult {
    let gists: [RamblingGist]
    let rawResponse: String
    let durationSeconds: Double
}

/// Service for extracting structured gists from raw rambling text
class RamblingToGistService {

    // MARK: - Main Extraction

    /// Extract gists from raw rambling text
    /// Chunks the text and generates gist variants for each chunk
    func extractGists(from ramblingText: String, temperature: Double = 0.2) async throws -> [RamblingGist] {
        let result = try await extractGistsWithMetadata(from: ramblingText, temperature: temperature)
        return result.gists
    }

    /// Extract gists with full metadata for fidelity testing
    func extractGistsWithMetadata(from ramblingText: String, temperature: Double = 0.2) async throws -> ExtractionResult {
        guard !ramblingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RamblingGistError.emptyInput
        }

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildExtractionPrompt(ramblingText: ramblingText)

        print("🔄 [RamblingToGist] Calling Claude API (temp: \(temperature))...")
        print("   - System prompt: \(systemPrompt.prefix(200))...")
        print("   - User prompt length: \(userPrompt.count) chars")

        let startTime = Date()
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 32000]
        )
        let elapsed = Date().timeIntervalSince(startTime)

        print("✅ [RamblingToGist] API response received in \(String(format: "%.1f", elapsed))s")
        print("   - Response length: \(response.count) chars")
        print("   - Response preview: \(response.prefix(500))...")

        let gists = try parseExtractionResponse(response, originalText: ramblingText)

        return ExtractionResult(
            gists: gists,
            rawResponse: response,
            durationSeconds: elapsed
        )
    }

    // MARK: - Prompt Building

    func buildSystemPrompt() -> String {
        """
        You are a structural extraction system analyzing raw rambling text.

        Your job is to:
        1. IDENTIFY functional chunks — groups of sentences that perform one structural job
        2. EXTRACT structural gists from each chunk for embedding/matching
        3. PRESERVE the original text exactly (no editing, smoothing, or reorganizing)

        You must not:
        - improve the writing
        - infer intent beyond observable text
        - collapse or reorganize the content
        - add content that isn't there
        - smooth transitions between chunks

        CRITICAL: Preserve the mess. Preserve the structure. Extract what's there.

        ═══════════════════════════════════════════════════════════════════════════════
        FRAME ENUM (used in gist_a and gist_b) — 10 Rambling Frames
        ═══════════════════════════════════════════════════════════════════════════════

        | Frame               | Use When                                                                        | Example                                                  |
        |---------------------|---------------------------------------------------------------------------------|----------------------------------------------------------|
        | personal_narrative  | Recounting something that happened, describing a scene witnessed or experienced | "I was sitting on this ridge and nothing was moving..."  |
        | factual_claim       | Stating a fact, stat, finding, data point, or sourced reference                 | "Mature bucks shift nocturnal 3 days before pressure"    |
        | wondering           | Asking a question out loud, genuine or rhetorical, about something unresolved   | "Why do deer just disappear right when rut kicks in?"    |
        | problem_statement   | Identifying something broken, wrong, contradicted, or not working               | "The morning hunt thing doesn't hold up with thermal data"|
        | explanation         | Describing how something works — mechanism, process, or cause-effect            | "Thermals pull scent downhill at first light and..."     |
        | comparison          | Mapping the subject onto something else — analogy, parallel, different domain   | "Same as how fish hold on current seams"                 |
        | stakes_declaration  | Declaring why something matters, what's at risk, speaking to listener           | "If you're still hunting mornings, you're burning sits"  |
        | pattern_notice      | Observing shared structure/cause/behavior across separate observations           | "Same pattern I see in the Illinois rut data"            |
        | correction          | Explicitly replacing a prior belief with a better one, including hedges         | "I used to think pressure but it's actually thermals"    |
        | takeaway            | Collapsing into a bottom-line conclusion or forward-looking statement           | "So the whole point is: hunt evenings, full stop"        |

        DISAMBIGUATION (when two frames could fit):
        - explanation vs pattern_notice: explanation describes ONE mechanism; pattern_notice CONNECTS two separate observations
        - problem_statement vs correction: problem_statement identifies a gap in the world; correction replaces a specific belief
        - personal_narrative vs stakes_declaration: narrative recounts what happened; stakes_declaration declares why it matters to the listener
        - factual_claim vs explanation: factual_claim is a discrete stated truth; explanation is a mechanistic cause-effect description
        - When in doubt, choose the frame that describes what the speaker is DOING, not what the content is ABOUT

        ═══════════════════════════════════════════════════════════════════════════════
        TWO GIST VARIANTS (REQUIRED FOR EACH CHUNK)
        ═══════════════════════════════════════════════════════════════════════════════

        1. gist_a — DETERMINISTIC (strict, minimal, routing-safe)
        ───────────────────────────────────────────────────────────────────────────────
        Purpose: Hard matching, low variance, maximum stability

        - subject: Array of concrete nouns only. No verbs, adjectives, or tone.
        - premise: One neutral declarative sentence describing observable action only.
        - frame: ONE value from Frame enum (snake_case).

        Rules:
        - No tone, no intent, no persuasion, no interpretation
        - Observable only — if you can't point to it in the text, don't include it

        2. gist_b — FLEXIBLE (still non-interpretive, but more natural)
        ───────────────────────────────────────────────────────────────────────────────
        Purpose: Semantic matching, human debugging, slightly richer signal

        - subject: Array of noun phrases, may include light modifiers from text.
        - premise: One sentence describing what the chunk accomplishes, plain language.
        - frame: ONE value from Frame enum (snake_case).

        Rules:
        - Still no intent, persuasion, or evaluation
        - May use natural phrasing
        - Must be grounded in observable text
        - NOT a topic summary — a controlled structural description

        ═══════════════════════════════════════════════════════════════════════════════
        OPTIONAL: RHETORICAL MOVE CLASSIFICATION
        ═══════════════════════════════════════════════════════════════════════════════

        If you can identify a rhetorical move, include it. Otherwise omit.

        HOOK: personal-stake, shocking-fact, question-hook, scene-set
        SETUP: common-belief, historical-context, define-frame, stakes-establishment
        TENSION: complication, counterargument, contradiction, mystery-raise
        REVELATION: hidden-truth, reframe, root-cause, connection-reveal
        EVIDENCE: evidence-stack, authority-cite, data-present, case-study, analogy
        CLOSING: synthesis, implication, future-project, viewer-address

        ═══════════════════════════════════════════════════════════════════════════════
        TELEMETRY (COUNTABLE ONLY)
        ═══════════════════════════════════════════════════════════════════════════════

        dominant_stance: "ASSERTING" | "QUESTIONING" | "MIXED"

        perspective_counts:
        - first_person: # of sentences with I/me/my/we/us/our
        - second_person: # of sentences with you/your
        - third_person: # of sentences with he/she/they/it or no personal pronoun

        sentence_flags:
        - number, temporal, contrast, question, quote, spatial, technical

        ═══════════════════════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════════════════════

        Output a JSON object with a "chunks" array:
        {
          "chunks": [
            {
              "chunk_index": 0,
              "source_text": "exact verbatim text from the rambling for this chunk",
              "gist_a": {
                "subject": ["noun1", "noun2"],
                "premise": "Neutral observable statement.",
                "frame": "frame_value"
              },
              "gist_b": {
                "subject": ["noun phrase 1", "noun phrase 2"],
                "premise": "Natural language structural description.",
                "frame": "frame_value"
              },
              "brief_description": "30-40 word description of what this chunk DOES structurally.",
              "move_label": "optional-move-label",
              "confidence": 0.85,
              "telemetry": {
                "dominant_stance": "ASSERTING",
                "perspective_counts": {
                  "first_person": 3,
                  "second_person": 0,
                  "third_person": 1
                },
                "sentence_flags": {
                  "number": 1,
                  "temporal": 0,
                  "contrast": 1,
                  "question": 0,
                  "quote": 0,
                  "spatial": 0,
                  "technical": 0
                }
              }
            }
          ]
        }

        VALIDATION:
        - source_text MUST be verbatim from the input (no editing)
        - gist_a.subject must be nouns only
        - frame must be from the enum (snake_case)
        - Output ONLY valid JSON. No markdown. No commentary.
        """
    }

    func buildExtractionPrompt(ramblingText: String) -> String {
        let wordCount = ramblingText.split(separator: " ").count

        return """
        Analyze this raw rambling text and extract structural chunks with gists.

        INSTRUCTIONS:
        1. Read through the entire text
        2. Identify chunk boundaries where the rhetorical FUNCTION changes — even when the topic stays the same. A specific spatial walkthrough (distances, routes, sequences) and the conclusion drawn from it are separate chunks. A quantitative data point and a personal anecdote mentioned alongside it are separate chunks. A technical caveat and the value proposition that follows it are separate chunks. Topic continuity is NOT a reason to keep content merged. HOWEVER: when the speaker is recapping or summarizing previously stated points, keep the recap as a single chunk — do not split individual recap sentences into separate chunks.
        3. For each chunk, extract BOTH gist variants
        4. Preserve the EXACT source text for each chunk (verbatim, no editing)
        5. Target chunks of 40-150 words each (flexible based on functional boundaries). Shorter chunks are acceptable when a clear functional boundary exists within a passage, but do not split below 40 words unless the content is a standalone question or single data point. Aim for 12-18 chunks on a typical 1500-2000 word rambling.

        RAW RAMBLING TEXT (\(wordCount) words):
        ═══════════════════════════════════════════════════════════════════════════════

        \(ramblingText)

        ═══════════════════════════════════════════════════════════════════════════════

        Output a JSON object with a "chunks" array containing all identified chunks.
        Each chunk needs: chunk_index, source_text (verbatim), gist_a, gist_b, brief_description.
        Optional: move_label, confidence, telemetry.
        """
    }

    // MARK: - Response Parsing

    private func parseExtractionResponse(_ response: String, originalText: String) throws -> [RamblingGist] {
        let jsonString = extractJSON(from: response)

        guard !jsonString.isEmpty else {
            throw RamblingGistError.invalidResponse("Could not extract JSON from response")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw RamblingGistError.invalidResponse("Could not convert to data")
        }

        do {
            let parsed = try JSONDecoder().decode(RamblingExtractionResponse.self, from: data)

            var gists: [RamblingGist] = []
            for chunk in parsed.chunks {
                if let gist = chunk.toRamblingGist() {
                    gists.append(gist)
                } else {
                    print("⚠️ Failed to parse chunk \(chunk.chunkIndex)")
                }
            }

            return gists.sorted { $0.chunkIndex < $1.chunkIndex }
        } catch {
            throw RamblingGistError.parseError("Failed to parse response: \(error.localizedDescription)")
        }
    }

    private func extractJSON(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if let start = text.range(of: "```json") {
            text = String(text[start.upperBound...])
        } else if let start = text.range(of: "```") {
            text = String(text[start.upperBound...])
        }

        if let end = text.range(of: "```", options: .backwards) {
            text = String(text[..<end.lowerBound])
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON object
        if let start = text.firstIndex(of: "{") {
            if let end = findMatchingBrace(in: text, from: start) {
                return String(text[start...end])
            }
        }

        return text
    }

    private func findMatchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let char = text[index]

            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

// MARK: - Response Models

struct RamblingExtractionResponse: Codable {
    let chunks: [RamblingChunkAIResponse]
}

struct RamblingChunkAIResponse: Codable {
    let chunkIndex: Int
    let sourceText: String
    let gistA: GistAIResponse
    let gistB: GistAIResponse
    let briefDescription: String
    let moveLabel: String?
    let confidence: Double?
    let telemetry: TelemetryAIResponse?

    enum CodingKeys: String, CodingKey {
        case chunkIndex = "chunk_index"
        case sourceText = "source_text"
        case gistA = "gist_a"
        case gistB = "gist_b"
        case briefDescription = "brief_description"
        case moveLabel = "move_label"
        case confidence
        case telemetry
    }

    func toRamblingGist() -> RamblingGist? {
        guard let gistAConverted = gistA.toChunkGistA(),
              let gistBConverted = gistB.toChunkGistB() else {
            return nil
        }

        return RamblingGist(
            chunkIndex: chunkIndex,
            sourceText: sourceText,
            gistA: gistAConverted,
            gistB: gistBConverted,
            briefDescription: briefDescription,
            moveLabel: moveLabel,
            confidence: confidence,
            telemetry: telemetry?.toChunkTelemetry()
        )
    }
}

// MARK: - Errors

enum RamblingGistError: LocalizedError {
    case emptyInput
    case invalidResponse(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No text provided to analyze"
        case .invalidResponse(let msg):
            return "Invalid AI response: \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}
