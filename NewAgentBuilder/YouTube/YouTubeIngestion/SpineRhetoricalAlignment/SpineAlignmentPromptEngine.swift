//
//  SpineAlignmentPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import Foundation

struct SpineAlignmentPromptEngine {

    // MARK: - Generate Prompt

    static func generatePrompt(
        video: YouTubeVideo,
        spine: NarrativeSpine,
        rhetoricalSequence: RhetoricalSequence
    ) -> (system: String, user: String) {

        let systemPrompt = "You are a structural alignment analyst. You align narrative spine beats to rhetorical move sequences by matching content scope overlap. Return valid JSON only. Do not include any text outside the JSON object."

        // Build spine beats section
        var spineLines: [String] = []
        for beat in spine.beats {
            spineLines.append("  Beat \(beat.beatNumber) | function: \(beat.function)")
            spineLines.append("    sentence: \(beat.beatSentence)")
            spineLines.append("    contentTag: \(beat.contentTag)")
        }
        let spineSection = spineLines.joined(separator: "\n")

        // Build rhetorical moves section
        var moveLines: [String] = []
        for move in rhetoricalSequence.moves {
            var line = "  Chunk \(move.chunkIndex) | moveType: \(move.moveType.rawValue)"
            line += " | \(move.briefDescription)"
            if let gistA = move.gistA {
                line += "\n    gistA premise: \(gistA.premise)"
            }
            if let gistB = move.gistB {
                line += "\n    gistB premise: \(gistB.premise)"
            }
            moveLines.append(line)
        }
        let moveSection = moveLines.joined(separator: "\n")

        let userPrompt = """
        You have two structural analyses of the same video. They slice the content at completely different granularities. The spine has \(spine.beats.count) beats (coarse grain — each beat is a major narrative construction move). The rhetorical sequence has \(rhetoricalSequence.moves.count) moves (fine grain — each move is a rhetorical device within a section).

        Your job: align each spine beat to the rhetorical moves that cover the same content. Match on MEANING and POSITION in the video, not on keyword overlap. The two systems describe the same content in completely different vocabularies.

        ---

        NARRATIVE SPINE (\(spine.beats.count) beats):

        \(spineSection)

        ---

        RHETORICAL MOVE SEQUENCE (\(rhetoricalSequence.moves.count) moves):

        \(moveSection)

        ---

        ALIGNMENT RULES — READ ALL FIVE BEFORE STARTING:

        1. ONE-TO-MANY IS THE NORMAL CASE. A single spine beat typically spans 3-5 rhetorical moves. The spine operates at coarser grain. Beat 4 (discovery) might span rhetorical moves 8 (scene-set), 9 (shocking-fact), and 10 (complication) because all three moves serve the same narrative function of delivering the discovery. Map ALL of them to that beat.

        2. MANY-TO-ONE IS POSSIBLE. One long rhetorical move (e.g., a sustained evidence-stack) may cover what the spine splits into beats 6, 7, and 8 (discovery, evidence, mechanism). Assign that single rhetorical move to EVERY spine beat it overlaps. Use overlapStrength "partial" for the beats where it only partially covers the content.

        3. ORPHAN RHETORICAL MOVES ARE EXPECTED. Some moves don't advance the causal chain — viewer-address, sponsor integrations, transitional scene-sets that serve the video's pacing but don't advance the structural argument. Put these in the "unmappedMoves" array with a brief reason. Do NOT force them into a beat.

        4. ORPHAN SPINE BEATS ARE A RED FLAG. If a spine beat has zero rhetorical moves mapped to it, something is wrong — either the rhetorical sequence missed that content or the spine beat doesn't correspond to delivered content. Try harder to find matching moves. If you truly cannot find any, include that beat number in the "orphanBeats" array.

        5. MATCH ON MEANING AND POSITION, NOT KEYWORDS. The spine beat's contentTag says "flew 200 acres, found 20 deer bedded, not a single buck." The rhetorical move's description says "Establishes dramatic physical setting through drone survey results." Those are the SAME moment described in different vocabularies. Use the video's chronological flow to anchor your alignment — earlier beats map to earlier moves, later beats to later moves. The ordering is your strongest signal.

        ---

        OVERLAP STRENGTH (assign one per mapped move):
        - "full" — the rhetorical move falls entirely within this spine beat's content scope
        - "partial" — the move straddles this beat and an adjacent beat, or covers only part of the beat's scope
        - "tangential" — the move touches the same content from a structurally different angle

        ---

        OUTPUT FORMAT — return this exact JSON structure:
        {
          "alignments": [
            {
              "beatNumber": 1,
              "function": "opening-anchor",
              "mappedMoves": [
                { "moveType": "scene-set", "chunkIndex": 0, "overlapStrength": "full" },
                { "moveType": "personal-stake", "chunkIndex": 1, "overlapStrength": "full" },
                { "moveType": "stakes-establishment", "chunkIndex": 2, "overlapStrength": "partial" }
              ],
              "rationale": "Beat 1 anchors the viewer in the physical experience. Moves 0-1 deliver this directly; move 2 partially overlaps as it begins the stakes framing."
            }
          ],
          "unmappedMoves": [
            { "chunkIndex": 31, "moveType": "viewer-address", "reason": "Direct viewer engagement, pacing only — does not advance the causal chain" }
          ],
          "orphanBeats": []
        }

        IMPORTANT CONSTRAINTS:
        - Every spine beat must appear in the alignments array, even if its mappedMoves is empty (and its beatNumber goes in orphanBeats)
        - Every rhetorical move must appear EITHER in a beat's mappedMoves OR in unmappedMoves — no moves should be silently dropped
        - The "function" field in each alignment must match the spine beat's original function label exactly
        - Return ONLY the JSON object. No markdown fences, no preamble, no commentary.
        """

        return (system: systemPrompt, user: userPrompt)
    }

    // MARK: - Parse Response

    static func parseResponse(
        _ text: String,
        video: YouTubeVideo,
        spine: NarrativeSpine,
        runNumber: Int = 1
    ) throws -> SpineRhetoricalAlignment {
        // 1. Clean up response
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Extract JSON if wrapped in other text
        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw SpineAlignmentError.parseFailed("Could not convert response to UTF-8 data")
        }

        // 3. Debug pass — log root keys
        if let generic = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            let keys = generic.keys.sorted().joined(separator: ", ")
            let alignCount = (generic["alignments"] as? [[String: Any]])?.count ?? 0
            let unmappedCount = (generic["unmappedMoves"] as? [[String: Any]])?.count ?? 0
            let orphanCount = (generic["orphanBeats"] as? [Any])?.count ?? 0
            print("📋 Alignment JSON keys: [\(keys)], alignments: \(alignCount), unmapped: \(unmappedCount), orphans: \(orphanCount)")
        }

        // 4. Decode to typed response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response: AlignmentRawResponse
        do {
            response = try decoder.decode(AlignmentRawResponse.self, from: jsonData)
        } catch {
            // WHAT: Decode failed
            print("❌ ALIGNMENT JSON PARSE FAILURE — Full raw JSON below:")
            print("─── BEGIN RAW JSON ───")
            print(cleaned.prefix(3000))
            print("─── END RAW JSON ───")

            // WHY: Extract specific DecodingError details
            let detail: String
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let ctx):
                    let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Type mismatch at '\(path)': expected \(type), debug: \(ctx.debugDescription)"
                case .keyNotFound(let key, let ctx):
                    let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Missing key '\(key.stringValue)' at '\(path)': \(ctx.debugDescription)"
                case .valueNotFound(let type, let ctx):
                    let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Null value for non-optional \(type) at '\(path)': \(ctx.debugDescription)"
                case .dataCorrupted(let ctx):
                    let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    detail = "Data corrupted at '\(path)': \(ctx.debugDescription)"
                @unknown default:
                    detail = "Unknown DecodingError: \(error)"
                }
                print("❌ DecodingError detail: \(detail)")
            } else {
                detail = "\(error)"
                print("❌ Non-DecodingError: \(detail)")
            }

            // Per-field isolation
            print("─── PER-FIELD DECODE ISOLATION ───")
            let fieldsOk: [String: Bool] = [
                "alignments": (try? decoder.decode(AlignmentDiag.AlignmentsOnly.self, from: jsonData)) != nil,
                "unmappedMoves": (try? decoder.decode(AlignmentDiag.UnmappedOnly.self, from: jsonData)) != nil,
                "orphanBeats": (try? decoder.decode(AlignmentDiag.OrphansOnly.self, from: jsonData)) != nil
            ]
            for (field, ok) in fieldsOk.sorted(by: { $0.key < $1.key }) {
                print("  \(ok ? "✅" : "❌") \(field)")
            }

            // If alignments failed, try each individually
            if fieldsOk["alignments"] != true,
               let generic = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let alignArray = generic["alignments"] as? [[String: Any]] {
                print("─── PER-ALIGNMENT ISOLATION (\(alignArray.count) alignments) ───")
                for (idx, dict) in alignArray.enumerated() {
                    do {
                        let data = try JSONSerialization.data(withJSONObject: dict)
                        _ = try decoder.decode(RawBeatAlignment.self, from: data)
                        print("  ✅ Alignment \(idx)")
                    } catch {
                        print("  ❌ Alignment \(idx): \(error)")
                        print("     Raw keys: \(dict.keys.sorted().joined(separator: ", "))")
                    }
                }
            }

            print("─── END DIAGNOSTIC ───")
            throw SpineAlignmentError.parseFailed("JSON decode failed: \(detail)")
        }

        // 5. Validate function labels
        for alignment in response.alignments {
            if !NarrativeSpineBeat.isKnownFunction(alignment.function) {
                print("⚠️ Unknown function label '\(alignment.function)' on alignment beat \(alignment.beatNumber)")
            }
        }

        // 6. Validate move types
        for alignment in response.alignments {
            for move in alignment.mappedMoves {
                if RhetoricalMoveType.parse(move.moveType) == nil {
                    print("⚠️ Unknown move type '\(move.moveType)' in alignment beat \(alignment.beatNumber)")
                }
            }
        }
        for unmapped in response.unmappedMoves {
            if RhetoricalMoveType.parse(unmapped.moveType) == nil {
                print("⚠️ Unknown move type '\(unmapped.moveType)' in unmapped moves")
            }
        }

        // 7. Build content tag map from spine for reference
        let contentTagMap: [Int: String] = Dictionary(
            uniqueKeysWithValues: spine.beats.map { ($0.beatNumber, $0.contentTag) }
        )

        // 8. Construct typed models
        let beatAlignments = response.alignments.map { raw in
            BeatMoveAlignment(
                beatNumber: raw.beatNumber,
                function: raw.function,
                contentTag: contentTagMap[raw.beatNumber] ?? "",
                mappedMoves: raw.mappedMoves.map { mm in
                    MappedMove(
                        moveType: mm.moveType,
                        chunkIndex: mm.chunkIndex,
                        overlapStrength: mm.overlapStrength
                    )
                },
                rationale: raw.rationale
            )
        }

        let unmappedMoves = response.unmappedMoves.map { raw in
            UnmappedMove(
                chunkIndex: raw.chunkIndex,
                moveType: raw.moveType,
                reason: raw.reason
            )
        }

        let orphanBeats = response.orphanBeats

        // 9. Check for orphan beats (beats in alignments with empty mappedMoves)
        var allOrphans = Set(orphanBeats)
        for ba in beatAlignments where ba.mappedMoves.isEmpty {
            allOrphans.insert(ba.beatNumber)
        }
        if !allOrphans.isEmpty {
            print("⚠️ Orphan spine beats (no rhetorical moves mapped): \(allOrphans.sorted())")
        }

        // 10. Render text
        let renderedText = SpineRhetoricalAlignment.renderText(
            beatAlignments: beatAlignments,
            unmappedMoves: unmappedMoves,
            orphanBeats: Array(allOrphans).sorted()
        )

        let moveCount = video.rhetoricalSequence?.moves.count ?? 0

        let alignment = SpineRhetoricalAlignment(
            videoId: video.videoId,
            channelId: video.channelId,
            runNumber: runNumber,
            extractedAt: Date(),
            beatCount: spine.beats.count,
            moveCount: moveCount,
            beatAlignments: beatAlignments,
            unmappedMoves: unmappedMoves,
            orphanBeats: Array(allOrphans).sorted(),
            renderedText: renderedText
        )

        print("✅ Parsed alignment: \(beatAlignments.count) beats aligned, \(unmappedMoves.count) unmapped moves, \(allOrphans.count) orphan beats")
        return alignment
    }
}

// MARK: - Raw Response Types (intermediate decode targets)

private struct AlignmentRawResponse: Codable {
    let alignments: [RawBeatAlignment]
    let unmappedMoves: [RawUnmappedMove]
    let orphanBeats: [Int]
}

private struct RawBeatAlignment: Codable {
    let beatNumber: Int
    let function: String
    let mappedMoves: [RawMappedMove]
    let rationale: String
}

private struct RawMappedMove: Codable {
    let moveType: String
    let chunkIndex: Int
    let overlapStrength: String
}

private struct RawUnmappedMove: Codable {
    let chunkIndex: Int
    let moveType: String
    let reason: String
}

// MARK: - Diagnostic Isolation Types

private enum AlignmentDiag {
    struct AlignmentsOnly: Codable { let alignments: [RawBeatAlignment] }
    struct UnmappedOnly: Codable { let unmappedMoves: [RawUnmappedMove] }
    struct OrphansOnly: Codable { let orphanBeats: [Int] }
}
