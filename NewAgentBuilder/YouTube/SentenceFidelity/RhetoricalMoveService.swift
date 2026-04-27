//
//  RhetoricalMoveService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/28/26.
//

import Foundation

/// Service for extracting rhetorical move sequences from video chunks
/// and comparing sequences to find "structural twins" - videos that follow
/// the same argumentative script but with different topics.
class RhetoricalMoveService {

    static let shared = RhetoricalMoveService()

    // MARK: - Main Extraction

    /// Extract rhetorical sequence from a video's chunks
    /// Uses closed-set classification with the 25-move codebook
    func extractRhetoricalSequence(
        videoId: String,
        chunks: [Chunk],
        temperature: Double = 0.1
    ) async throws -> RhetoricalSequence {
        guard !chunks.isEmpty else {
            throw RhetoricalMoveError.noChunks
        }

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildExtractionPrompt(chunks: chunks)

        print("🔄 [RhetoricalMoveService] Starting extraction for video: \(videoId)")
        print("   - Chunks: \(chunks.count)")
        print("   - System prompt length: \(systemPrompt.count) chars")
        print("   - User prompt length: \(userPrompt.count) chars")
        print("   - Total prompt size: \((systemPrompt.count + userPrompt.count) / 1000)K chars")

        let startTime = Date()
        // Large videos can have 40+ chunks - each chunk produces ~400-500 tokens of output
        // 64000 tokens should handle videos with up to ~100 chunks
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 64000]
        )
        let elapsed = Date().timeIntervalSince(startTime)

        print("✅ [RhetoricalMoveService] API response received in \(String(format: "%.1f", elapsed))s")
        print("   - Response length: \(response.count) chars")
        if response.count < 1000 {
            print("   - Full response: \(response)")
        } else {
            print("   - Response preview: \(response.prefix(500))...")
        }

        let moves = try parseExtractionResponse(response, chunkCount: chunks.count)
        print("✅ [RhetoricalMoveService] Parsed \(moves.count) moves")

        return RhetoricalSequence(
            videoId: videoId,
            moves: moves,
            extractedAt: Date()
        )
    }

    /// Batch extract sequences for multiple videos (parallel, 10 at a time)
    func extractSequencesBatch(
        videos: [(videoId: String, chunks: [Chunk])],
        temperature: Double = 0.1,
        concurrency: Int = 10,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [String: RhetoricalSequence] {
        let total = videos.count
        var completed = 0

        // Use actor for thread-safe results collection
        actor ResultCollector {
            var results: [String: RhetoricalSequence] = [:]

            func add(videoId: String, sequence: RhetoricalSequence) {
                results[videoId] = sequence
            }

            func getResults() -> [String: RhetoricalSequence] {
                return results
            }
        }

        let collector = ResultCollector()

        // Process in batches of `concurrency`
        for batchStart in stride(from: 0, to: videos.count, by: concurrency) {
            let batchEnd = min(batchStart + concurrency, videos.count)
            let batch = Array(videos[batchStart..<batchEnd])

            // Run batch in parallel
            await withTaskGroup(of: (String, RhetoricalSequence?).self) { group in
                for video in batch {
                    group.addTask {
                        do {
                            let sequence = try await self.extractRhetoricalSequence(
                                videoId: video.videoId,
                                chunks: video.chunks,
                                temperature: temperature
                            )
                            return (video.videoId, sequence)
                        } catch {
                            print("⚠️ Failed to extract sequence for \(video.videoId): \(error)")
                            return (video.videoId, nil)
                        }
                    }
                }

                // Collect results as they complete
                for await (videoId, sequence) in group {
                    if let seq = sequence {
                        await collector.add(videoId: videoId, sequence: seq)
                    }
                    completed += 1

                    await MainActor.run {
                        onProgress?(completed, total)
                    }
                }
            }
        }

        return await collector.getResults()
    }

    // MARK: - Chunk-by-Chunk Extraction (Incremental)

    /// Extract rhetorical move for a SINGLE chunk
    /// Returns the move analysis for just one chunk
    func extractSingleChunkMove(
        chunk: Chunk,
        chunkIndex: Int,
        videoId: String,
        temperature: Double = 0.1
    ) async throws -> RhetoricalMove {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let systemPrompt = buildSingleChunkSystemPrompt()
        let userPrompt = buildSingleChunkPrompt(chunk: chunk, chunkIndex: chunkIndex)

        print("🔄 [RhetoricalMove] Extracting chunk \(chunkIndex) for video: \(videoId)")

        let startTime = Date()
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 4000]  // Single chunk needs much less
        )
        let elapsed = Date().timeIntervalSince(startTime)

        print("✅ [RhetoricalMove] Chunk \(chunkIndex) done in \(String(format: "%.1f", elapsed))s")

        return try parseSingleChunkResponse(response, expectedIndex: chunkIndex)
    }

    /// Extract rhetorical sequence chunk-by-chunk with incremental saving
    /// Calls onMoveExtracted after EACH chunk so progress can be saved
    /// Processes chunks in parallel batches for speed
    func extractRhetoricalSequenceIncremental(
        videoId: String,
        chunks: [Chunk],
        existingMoves: [RhetoricalMove] = [],  // Resume from partial progress
        temperature: Double = 0.1,
        concurrency: Int = 10,  // Max parallel requests
        onMoveExtracted: ((RhetoricalMove, Int, Int) async -> Void)? = nil,  // (move, current, total)
        onProgress: ((String) -> Void)? = nil
    ) async throws -> RhetoricalSequence {
        guard !chunks.isEmpty else {
            throw RhetoricalMoveError.noChunks
        }

        // Build set of already-processed chunk indices
        let processedIndices = Set(existingMoves.map { $0.chunkIndex })

        let total = chunks.count
        let alreadyProcessed = existingMoves.count

        print("\n========================================")
        print("PARALLEL RHETORICAL EXTRACTION")
        print("========================================")
        print("Video: \(videoId)")
        print("Total chunks: \(total)")
        print("Already processed: \(alreadyProcessed)")
        print("Remaining: \(total - alreadyProcessed)")
        print("Concurrency: \(concurrency)")

        // Collect chunks that need processing
        var chunksToProcess: [(index: Int, chunk: Chunk)] = []
        for (index, chunk) in chunks.enumerated() {
            if !processedIndices.contains(index) {
                chunksToProcess.append((index: index, chunk: chunk))
            } else {
                print("⏭️ Skipping chunk \(index) (already processed)")
            }
        }

        // Actor to safely collect results and track progress
        actor ResultCollector {
            var moves: [RhetoricalMove]
            var processed: Int
            let total: Int
            let onMoveExtracted: ((RhetoricalMove, Int, Int) async -> Void)?

            init(existingMoves: [RhetoricalMove], total: Int, onMoveExtracted: ((RhetoricalMove, Int, Int) async -> Void)?) {
                self.moves = existingMoves
                self.processed = existingMoves.count
                self.total = total
                self.onMoveExtracted = onMoveExtracted
            }

            func addMove(_ move: RhetoricalMove) async {
                moves.append(move)
                processed += 1
                await onMoveExtracted?(move, processed, total)
            }

            func getMoves() -> [RhetoricalMove] {
                return moves
            }

            func getProcessedCount() -> Int {
                return processed
            }
        }

        let collector = ResultCollector(
            existingMoves: existingMoves,
            total: total,
            onMoveExtracted: onMoveExtracted
        )

        // Process in parallel batches
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0

            for (index, chunk) in chunksToProcess {
                // Wait if we've hit concurrency limit
                if inFlight >= concurrency {
                    await group.next()
                    inFlight -= 1
                }

                // Stagger requests slightly (100ms apart)
                if inFlight > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                inFlight += 1
                let currentProcessed = await collector.getProcessedCount()
                onProgress?("Processing chunks... (\(currentProcessed)/\(total))")

                group.addTask {
                    do {
                        let move = try await self.extractSingleChunkMove(
                            chunk: chunk,
                            chunkIndex: index,
                            videoId: videoId,
                            temperature: temperature
                        )

                        await collector.addMove(move)
                        print("✓ Chunk \(index): \(move.moveType.rawValue) (conf: \(String(format: "%.0f", move.confidence * 100))%)")

                    } catch {
                        print("✗ Chunk \(index) failed: \(error)")
                        // Create a fallback move so we don't lose position
                        let fallback = RhetoricalMove(
                            chunkIndex: index,
                            moveType: .synthesis,
                            confidence: 0.0,
                            alternateType: nil,
                            alternateConfidence: nil,
                            briefDescription: "[EXTRACTION FAILED: \(error.localizedDescription)]"
                        )
                        await collector.addMove(fallback)
                    }
                }
            }

            // Wait for remaining tasks
            await group.waitForAll()
        }

        // Get final results and sort by chunk index
        var allMoves = await collector.getMoves()
        allMoves.sort { $0.chunkIndex < $1.chunkIndex }

        print("✅ Parallel extraction complete: \(allMoves.count) moves")

        return RhetoricalSequence(
            videoId: videoId,
            moves: allMoves,
            extractedAt: Date()
        )
    }

    // MARK: - Single Chunk Prompt Building

    private func buildSingleChunkSystemPrompt() -> String {
        """
        You are an expert rhetorical analyst. Classify this SINGLE chunk into exactly ONE rhetorical move.

        VALID MOVE LABELS (use EXACTLY one - all are hyphenated):
        personal-stake, shocking-fact, question-hook, scene-set,
        common-belief, historical-context, define-frame, stakes-establishment,
        complication, counterargument, contradiction, mystery-raise,
        hidden-truth, reframe, root-cause, connection-reveal,
        evidence-stack, authority-cite, data-present, case-study, analogy,
        synthesis, implication, future-project, viewer-address

        (For context: first 4 are hooks, next 4 setup, next 4 tension, next 4 revelation, next 5 evidence, last 4 closing)

        FRAME VALUES (for gist_a.frame and gist_b.frame fields ONLY - these are NOT move labels):
        personal_narrative, factual_claim, wondering, problem_statement, explanation, comparison, stakes_declaration, pattern_notice, correction, takeaway

        DOMINANT_STANCE (for telemetry field - use EXACTLY one of these three):
        - "ASSERTING" = declarative statements, claims, explanations, demonstrations
        - "QUESTIONING" = questions, uncertainty, inquiry
        - "MIXED" = both asserting and questioning present
        ❌ DO NOT invent values like "DEMONSTRATING", "EXPLAINING", "NARRATING"

        OUTPUT FORMAT (JSON):
        {
          "chunk_index": 0,
          "move_label": "personal-stake",
          "confidence": 0.92,
          "alternate_label": "stakes-establishment",
          "alternate_confidence": 0.08,
          "brief_description": "30-40 words on rhetorical FUNCTION",
          "gist_a": { "subject": ["noun1"], "premise": "Statement.", "frame": "reveal" },
          "gist_b": { "subject": ["phrase1"], "premise": "Statement.", "frame": "reveal" },
          "expanded_description": "3-5 sentences.",
          "telemetry": {
            "dominant_stance": "ASSERTING",
            "perspective_counts": { "first_person": 0, "second_person": 0, "third_person": 0 },
            "sentence_flags": { "number": 0, "temporal": 0, "contrast": 0, "question": 0, "quote": 0, "spatial": 0, "technical": 0 }
          }
        }

        Output ONLY valid JSON. No markdown.
        """
    }

    private func buildSingleChunkPrompt(chunk: Chunk, chunkIndex: Int) -> String {
        """
        Analyze this single chunk and classify it into ONE rhetorical move.

        [CHUNK \(chunkIndex)]
        Position: \(String(format: "%.0f", chunk.positionInVideo * 100))% (\(chunk.positionLabel))
        Sentences: \(chunk.sentenceCount)

        FULL TEXT:
        \(chunk.fullText)

        Output a JSON object with the move analysis for chunk_index \(chunkIndex).
        Focus on rhetorical FUNCTION, not topic content.
        """
    }

    private func parseSingleChunkResponse(_ response: String, expectedIndex: Int) throws -> RhetoricalMove {
        let jsonString = extractJSON(from: response)

        guard !jsonString.isEmpty else {
            throw RhetoricalMoveError.invalidResponse("Could not extract JSON from response")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw RhetoricalMoveError.invalidResponse("Could not convert to data")
        }

        do {
            let aiMove = try JSONDecoder().decode(RhetoricalMoveAIResponse.self, from: data)

            if let move = aiMove.toRhetoricalMove() {
                return move
            } else {
                print("⚠️ Invalid move label: \(aiMove.moveLabel)")
                // Return fallback
                return RhetoricalMove(
                    chunkIndex: expectedIndex,
                    moveType: .synthesis,
                    confidence: 0.1,
                    alternateType: nil,
                    alternateConfidence: nil,
                    briefDescription: aiMove.briefDescription + " [INVALID LABEL: \(aiMove.moveLabel)]"
                )
            }
        } catch {
            throw RhetoricalMoveError.parseError("Failed to parse single chunk: \(error.localizedDescription)")
        }
    }

    // MARK: - Sequence Comparison

    /// Compare two rhetorical sequences and return a match score (0-1)
    /// Uses Levenshtein edit distance normalized by max length
    func compareSequences(
        seq1: RhetoricalSequence,
        seq2: RhetoricalSequence
    ) -> Double {
        let moves1 = seq1.moveSequence
        let moves2 = seq2.moveSequence

        guard !moves1.isEmpty || !moves2.isEmpty else { return 1.0 }
        guard !moves1.isEmpty && !moves2.isEmpty else { return 0.0 }

        let editDistance = levenshteinDistance(moves1, moves2)
        let maxLen = max(moves1.count, moves2.count)

        // Convert to similarity (1 = identical, 0 = completely different)
        return 1.0 - (Double(editDistance) / Double(maxLen))
    }

    /// Find all twin pairs within a set of sequences, ranked by match score
    func findTwinPairs(
        sequences: [String: RhetoricalSequence],
        minScore: Double = 0.5
    ) -> [RhetoricalTwinResult] {
        var results: [RhetoricalTwinResult] = []

        let videoIds = Array(sequences.keys).sorted()

        // Compare all pairs
        for i in 0..<videoIds.count {
            for j in (i + 1)..<videoIds.count {
                let id1 = videoIds[i]
                let id2 = videoIds[j]

                guard let seq1 = sequences[id1],
                      let seq2 = sequences[id2] else { continue }

                let score = compareSequences(seq1: seq1, seq2: seq2)

                if score >= minScore {
                    let editDist = levenshteinDistance(seq1.moveSequence, seq2.moveSequence)
                    let aligned = alignSequences(seq1: seq1, seq2: seq2)

                    let result = RhetoricalTwinResult(
                        video1Id: id1,
                        video2Id: id2,
                        sequence1: seq1,
                        sequence2: seq2,
                        matchScore: score,
                        editDistance: editDist,
                        alignedMoves: aligned
                    )
                    results.append(result)
                }
            }
        }

        // Sort by match score (highest first)
        return results.sorted { $0.matchScore > $1.matchScore }
    }

    /// Align two sequences for side-by-side visualization
    /// Uses dynamic programming to find optimal alignment
    func alignSequences(
        seq1: RhetoricalSequence,
        seq2: RhetoricalSequence
    ) -> [AlignedMovePair] {
        let moves1 = seq1.moves
        let moves2 = seq2.moves

        // Use Needleman-Wunsch style alignment
        let alignment = needlemanWunschAlign(moves1, moves2)
        return alignment
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        """
        You are an expert rhetorical analyst. Your task is to classify each chunk of a YouTube video transcript into exactly ONE rhetorical move from a fixed codebook, AND generate three gist variants for downstream matching.

        CRITICAL RULES:
        1. Use ONLY the move labels from the codebook below. No creativity. No new labels.
        2. Each chunk gets exactly ONE move classification.
        3. Provide a confidence score (0.0 to 1.0) for your classification.
        4. If uncertain, provide an alternate move label with its confidence.
        5. Generate ALL THREE gist variants for each chunk.
        6. Output ONLY valid JSON. No commentary. No markdown.

        ═══════════════════════════════════════════════════════════════════════════════
        VALID MOVE LABELS (use EXACTLY one - all are hyphenated)
        ═══════════════════════════════════════════════════════════════════════════════

        personal-stake, shocking-fact, question-hook, scene-set,
        common-belief, historical-context, define-frame, stakes-establishment,
        complication, counterargument, contradiction, mystery-raise,
        hidden-truth, reframe, root-cause, connection-reveal,
        evidence-stack, authority-cite, data-present, case-study, analogy,
        synthesis, implication, future-project, viewer-address

        (For context only: first 4 are opening hooks, next 4 are setup/framing,
        next 4 are tension-building, next 4 are revelations, next 5 are evidence,
        last 4 are closing moves)

        ═══════════════════════════════════════════════════════════════════════════════
        FRAME VALUES (for gist_a.frame and gist_b.frame fields ONLY)
        ═══════════════════════════════════════════════════════════════════════════════

        These are NOT move labels - only use in the "frame" field inside gist_a/gist_b:
        personal_narrative, factual_claim, wondering, problem_statement, explanation,
        comparison, stakes_declaration, pattern_notice, correction, takeaway

        ═══════════════════════════════════════════════════════════════════════════════
        THREE GIST VARIANTS (REQUIRED FOR EACH CHUNK)
        ═══════════════════════════════════════════════════════════════════════════════

        For each chunk, you must generate THREE different gist representations:

        ───────────────────────────────────────────────────────────────────────────────
        1. briefDescription (30-40 words)
        ───────────────────────────────────────────────────────────────────────────────
        
        A natural language summary describing what the chunk DOES rhetorically, not 
        what it's ABOUT topically. Focus on the structural/persuasive function.
        
        Good: "Creator establishes personal credibility by sharing their three-year 
              research journey, then pivots to frame the stakes by explaining why 
              this overlooked detail matters to the viewer's daily life."
        
        Bad:  "Talks about research and why it matters." (too vague, too short)
        Bad:  "The creator spent three years researching..." (summarizes content, 
              not function)

        ───────────────────────────────────────────────────────────────────────────────
        2. gistA — DETERMINISTIC (strict, minimal, routing-safe)
        ───────────────────────────────────────────────────────────────────────────────
        
        Purpose: Hard matching, low variance, maximum stability
        
        - subject: Array of concrete nouns only. No verbs, no adjectives, no tone.
        - premise: One neutral declarative sentence describing observable rhetorical 
                   action only. No interpretation of intent or persuasion.
        - frame: ONE value from Frame enum above.
        
        Rules:
        - No tone, no intent, no persuasion, no interpretation
        - Observable structural moves only
        - If you can't point to it in the text, don't include it

        ───────────────────────────────────────────────────────────────────────────────
        3. gist_b — FLEXIBLE (still non-interpretive, but more natural)
        ───────────────────────────────────────────────────────────────────────────────

        Purpose: Semantic matching, human debugging, slightly richer signal

        - subject: Array of noun phrases, may include light modifiers if directly
                   supported by text.
        - premise: One sentence describing what the chunk accomplishes rhetorically,
                   in plain natural language.
        - frame: ONE value from Frame enum above.

        Rules:
        - Still no intent, persuasion, or evaluation
        - May use natural phrasing
        - Must still be grounded in observable rhetorical structure
        - This is NOT a topic summary — it's a controlled structural description

        ═══════════════════════════════════════════════════════════════════════════════
        EXPANDED DESCRIPTION (3-5 sentences)
        ═══════════════════════════════════════════════════════════════════════════════

        A fuller explanation of what the chunk DOES structurally. Not a summary of
        content — a description of function.

        Include:
        - What structural job this chunk performs in the video
        - How it connects to what likely came before/after
        - What technique or pattern the creator uses
        - Why this chunk exists at this point in the narrative

        Do NOT include:
        - Value judgments ("this is effective because...")
        - Speculation about creator intent
        - Summary of the topic/content itself

        ═══════════════════════════════════════════════════════════════════════════════
        TELEMETRY (COUNTABLE ONLY)
        ═══════════════════════════════════════════════════════════════════════════════

        Count these signals in the chunk text:

        dominant_stance: MUST be EXACTLY one of these three values:
        - "ASSERTING" = declarative statements, claims, explanations, demonstrations
        - "QUESTIONING" = questions, uncertainty, inquiry
        - "MIXED" = both asserting and questioning present
        ❌ DO NOT invent values like "DEMONSTRATING", "EXPLAINING", "NARRATING"

        perspective_counts:
        - first_person: # of sentences with I/me/my/we/us/our
        - second_person: # of sentences with you/your
        - third_person: # of sentences with he/she/they/it or no personal pronoun

        sentence_flags (count occurrences):
        - number: sentences containing numbers/statistics
        - temporal: sentences with time references (dates, "then", "later", etc.)
        - contrast: sentences with contrast markers ("but", "however", "yet")
        - question: sentences ending with ?
        - quote: sentences with attributed speech
        - spatial: sentences with location references
        - technical: sentences with domain-specific terminology

        ═══════════════════════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════════════════════

        Output a JSON object with a "moves" array. Use snake_case for ALL field names:
        {
          "moves": [
            {
              "chunk_index": 0,
              "move_label": "personal-stake",
              "confidence": 0.92,
              "alternate_label": "stakes-establishment",
              "alternate_confidence": 0.08,
              "brief_description": "Creator establishes personal credibility through their multi-year research investment, then transitions to frame why this commonly overlooked detail has direct implications for the viewer's understanding of the broader topic.",
              "gist_a": {
                "subject": ["creator", "research", "time investment"],
                "premise": "Creator states duration of personal research effort.",
                "frame": "expectation_setup"
              },
              "gist_b": {
                "subject": ["multi-year research journey", "personal credibility marker"],
                "premise": "The chunk establishes creator authority through stated time investment before pivoting to relevance.",
                "frame": "expectation_setup"
              },
              "expanded_description": "This chunk opens the video by establishing the creator's personal investment in the topic. It uses a temporal anchor to signal depth of commitment. The mention of obstacles creates a mini-narrative of struggle before the payoff. This functions as a hook that builds credibility through effort while simultaneously promising a revelation. The chunk sets up an expectation that what follows will be worth the wait.",
              "telemetry": {
                "dominant_stance": "ASSERTING",
                "perspective_counts": {
                  "first_person": 4,
                  "second_person": 0,
                  "third_person": 0
                },
                "sentence_flags": {
                  "number": 1,
                  "temporal": 2,
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

        ═══════════════════════════════════════════════════════════════════════════════
        VALIDATION RULES
        ═══════════════════════════════════════════════════════════════════════════════

        ⚠️ MOVE_LABEL VALIDATION (most common error):
        - move_label MUST be EXACTLY one of these 25 hyphenated labels:
          personal-stake, shocking-fact, question-hook, scene-set,
          common-belief, historical-context, define-frame, stakes-establishment,
          complication, counterargument, contradiction, mystery-raise,
          hidden-truth, reframe, root-cause, connection-reveal,
          evidence-stack, authority-cite, data-present, case-study, analogy,
          synthesis, implication, future-project, viewer-address

        ❌ INVALID move_label examples (DO NOT USE):
          - "application" ← This is a FRAME value, not a move label
          - "reveal" ← This is a FRAME value, not a move label
          - "explanation" ← This is a FRAME value, not a move label
          - "hook" ← This is a category name, not a move label
          - "evidence" ← Use "evidence-stack" instead
          - "revelation" ← Use "hidden-truth" or "reframe" instead

        OTHER RULES:
        - ALL field names must be snake_case
        - confidence: 0.0-1.0 reflecting fit quality
        - alternate_label: optional, also from 25 labels
        - brief_description: 30-40 words on rhetorical FUNCTION
        - gist_a/gist_b frame: one of 9 frame values (scene_set, investigation, etc.)
        - telemetry counts: integers only

        OUTPUT IS INVALID IF move_label is not from the 25 labels above.
        """
    }

    private func buildExtractionPrompt(chunks: [Chunk]) -> String {
        var chunksText = ""
        for (index, chunk) in chunks.enumerated() {
            let text = chunk.fullText
            chunksText += """

            ═══════════════════════════════════════════════════════════════════════════════
            [CHUNK \(index)]
            ═══════════════════════════════════════════════════════════════════════════════
            Position: \(String(format: "%.0f", chunk.positionInVideo * 100))% (\(chunk.positionLabel))
            Sentences: \(chunk.sentenceCount)

            FULL TEXT:
            \(text)

            """
        }

        return """
        Analyze the rhetorical function of each chunk in this video transcript.

        For each chunk:
        1. Classify it into exactly ONE move from the codebook
        2. Generate BOTH gist variants (gist_a and gist_b)
        3. Write an expanded_description (3-5 sentences on structural function)
        4. Count telemetry signals

        Focus on what the chunk DOES structurally, not its topic.

        CHUNKS TO ANALYZE:
        \(chunksText)

        Output a JSON object with a "moves" array containing exactly \(chunks.count) move analyses.
        Use snake_case for ALL field names.

        REQUIRED FIELDS FOR EACH MOVE (all snake_case):
        - chunk_index (integer)
        - move_label (from 25-move codebook)
        - confidence (0.0-1.0)
        - alternate_label (optional, if confidence < 0.8)
        - alternate_confidence (optional)
        - brief_description (30-40 words on rhetorical function)
        - gist_a: { subject: [nouns], premise: "neutral sentence", frame: "enum_value" }
        - gist_b: { subject: [noun phrases], premise: "natural sentence", frame: "enum_value" }
        - expanded_description (3-5 sentences on structural function)
        - telemetry: { dominant_stance, perspective_counts, sentence_flags }
        """
    }

    // MARK: - Response Parsing

    private func parseExtractionResponse(_ response: String, chunkCount: Int) throws -> [RhetoricalMove] {
        let jsonString = extractJSON(from: response)

        guard !jsonString.isEmpty else {
            throw RhetoricalMoveError.invalidResponse("Could not extract JSON from response")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw RhetoricalMoveError.invalidResponse("Could not convert to data")
        }

        do {
            let parsed = try JSONDecoder().decode(RhetoricalExtractionResponse.self, from: data)

            var moves: [RhetoricalMove] = []
            for aiMove in parsed.moves {
                if let move = aiMove.toRhetoricalMove() {
                    moves.append(move)
                } else {
                    print("⚠️ Invalid move label: \(aiMove.moveLabel)")
                    // Create a fallback with "synthesis" as default
                    let fallback = RhetoricalMove(
                        chunkIndex: aiMove.chunkIndex,
                        moveType: .synthesis,
                        confidence: 0.1,
                        alternateType: nil,
                        alternateConfidence: nil,
                        briefDescription: aiMove.briefDescription + " [INVALID LABEL: \(aiMove.moveLabel)]"
                    )
                    moves.append(fallback)
                }
            }

            return moves.sorted { $0.chunkIndex < $1.chunkIndex }
        } catch {
            throw RhetoricalMoveError.parseError("Failed to parse response: \(error.localizedDescription)")
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

    // MARK: - Multi-Stage Twin Finding

    /// Full multi-stage twin finding funnel
    /// Stage 1: Parent-level coarse filter
    /// Stage 2: Fine-grained scoring with same-parent tolerance
    /// Stage 3 (optional): AI semantic verification for disputed chunks
    func findTwinsMultiStage(
        sequences: [String: RhetoricalSequence],
        topKCoarse: Int = 10,
        minParentScore: Double = 0.6,
        runStage3: Bool = false,
        chunkTexts: [String: [String]]? = nil,       // videoId -> [chunkText] for Stage 3
        onProgress: ((String) -> Void)? = nil
    ) async -> [MultiStageTwinResult] {

        onProgress?("Stage 1: Coarse parent-level comparison...")

        // Stage 1: Coarse comparison at parent level
        let coarseResults = performStage1CoarseComparison(
            sequences: sequences,
            minScore: minParentScore
        )

        onProgress?("Stage 1 complete: \(coarseResults.count) pairs passed parent-level filter")

        // Take top K for Stage 2
        let topCoarse = Array(coarseResults.prefix(topKCoarse))

        onProgress?("Stage 2: Fine-grained comparison with same-parent tolerance...")

        // Stage 2: Fine comparison with same-parent tolerance
        var fineResults = performStage2FineComparison(coarseResults: topCoarse)

        onProgress?("Stage 2 complete: Computed fine scores for \(fineResults.count) pairs")

        // Stage 3 (optional): AI semantic verification
        if runStage3, let texts = chunkTexts {
            onProgress?("Stage 3: AI semantic verification for mismatched chunks...")

            fineResults = await performStage3SemanticVerification(
                fineResults: fineResults,
                chunkTexts: texts,
                onProgress: onProgress
            )

            onProgress?("Stage 3 complete")
        }

        // Convert to final results
        let finalResults = fineResults.map { fine -> MultiStageTwinResult in
            let adjustedScore: Double? = runStage3 ? computeAdjustedScore(for: fine) : nil

            return MultiStageTwinResult(
                video1Id: fine.video1Id,
                video2Id: fine.video2Id,
                sequence1: fine.sequence1,
                sequence2: fine.sequence2,
                stage1ParentScore: fine.parentMatchScore,
                stage2FineScore: fine.fineScore,
                stage3AdjustedScore: adjustedScore,
                chunkComparisons: fine.chunkComparisons
            )
        }

        // Sort by final score
        return finalResults.sorted { $0.finalScore > $1.finalScore }
    }

    // MARK: - Stage 1: Coarse Comparison (Parent Level)

    /// Compare all pairs at parent level only (6 categories)
    private func performStage1CoarseComparison(
        sequences: [String: RhetoricalSequence],
        minScore: Double
    ) -> [CoarseComparisonResult] {
        var results: [CoarseComparisonResult] = []

        let videoIds = Array(sequences.keys).sorted()

        for i in 0..<videoIds.count {
            for j in (i + 1)..<videoIds.count {
                let id1 = videoIds[i]
                let id2 = videoIds[j]

                guard let seq1 = sequences[id1],
                      let seq2 = sequences[id2] else { continue }

                let parents1 = seq1.parentSequence
                let parents2 = seq2.parentSequence

                let editDist = levenshteinDistanceCategories(parents1, parents2)
                let maxLen = max(parents1.count, parents2.count)
                let score = maxLen > 0 ? 1.0 - (Double(editDist) / Double(maxLen)) : 1.0

                if score >= minScore {
                    results.append(CoarseComparisonResult(
                        video1Id: id1,
                        video2Id: id2,
                        sequence1: seq1,
                        sequence2: seq2,
                        parentMatchScore: score,
                        parentEditDistance: editDist
                    ))
                }
            }
        }

        // Sort by parent match score (highest first)
        return results.sorted { $0.parentMatchScore > $1.parentMatchScore }
    }

    // MARK: - Stage 2: Fine Comparison (Same-Parent Tolerance)

    /// Fine-grained comparison with weighted scoring:
    /// - Exact match = 1.0
    /// - Same parent = 0.7
    /// - Different parent = 0.0
    private func performStage2FineComparison(
        coarseResults: [CoarseComparisonResult]
    ) -> [FineComparisonResult] {
        return coarseResults.map { coarse in
            let comparisons = computeChunkComparisons(
                moves1: coarse.sequence1.moves,
                moves2: coarse.sequence2.moves
            )

            let totalScore = comparisons.reduce(0.0) { $0 + $1.chunkScore }
            let fineScore = comparisons.isEmpty ? 0.0 : totalScore / Double(comparisons.count)

            return FineComparisonResult(
                video1Id: coarse.video1Id,
                video2Id: coarse.video2Id,
                sequence1: coarse.sequence1,
                sequence2: coarse.sequence2,
                parentMatchScore: coarse.parentMatchScore,
                fineScore: fineScore,
                chunkComparisons: comparisons
            )
        }
    }

    /// Create chunk-by-chunk comparison between two videos
    private func computeChunkComparisons(
        moves1: [RhetoricalMove],
        moves2: [RhetoricalMove]
    ) -> [ChunkComparison] {
        var comparisons: [ChunkComparison] = []

        let maxChunks = max(moves1.count, moves2.count)

        for i in 0..<maxChunks {
            let move1 = i < moves1.count ? moves1[i] : nil
            let move2 = i < moves2.count ? moves2[i] : nil

            let score: Double
            if let m1 = move1, let m2 = move2 {
                if m1.moveType == m2.moveType {
                    score = 1.0  // Exact match
                } else if m1.moveType.category == m2.moveType.category {
                    score = 0.7  // Same parent
                } else {
                    score = 0.0  // Different parent
                }
            } else {
                score = 0.0  // Gap
            }

            comparisons.append(ChunkComparison(
                chunkIndex: i,
                move1: move1,
                move2: move2,
                chunkScore: score
            ))
        }

        return comparisons
    }

    // MARK: - Stage 3: AI Semantic Verification

    /// Use AI to verify if mismatched chunks are doing the same rhetorical function
    private func performStage3SemanticVerification(
        fineResults: [FineComparisonResult],
        chunkTexts: [String: [String]],
        onProgress: ((String) -> Void)?
    ) async -> [FineComparisonResult] {

        var updatedResults: [FineComparisonResult] = []

        for fine in fineResults {
            // Find chunks that need verification (same parent but different child)
            let chunksToVerify = fine.chunkComparisons.enumerated().filter { _, comp in
                !comp.isExactMatch && comp.isSameParent && !comp.isGap
            }

            if chunksToVerify.isEmpty {
                updatedResults.append(fine)
                continue
            }

            onProgress?("Verifying \(chunksToVerify.count) chunks for \(fine.video1Id) ↔ \(fine.video2Id)")

            // Get chunk texts
            let texts1 = chunkTexts[fine.video1Id] ?? []
            let texts2 = chunkTexts[fine.video2Id] ?? []

            // Build requests for chunks that need verification
            var requests: [SemanticComparisonRequest] = []
            for (_, comp) in chunksToVerify {
                guard let m1 = comp.move1, let m2 = comp.move2 else { continue }

                let text1 = comp.chunkIndex < texts1.count ? texts1[comp.chunkIndex] : ""
                let text2 = comp.chunkIndex < texts2.count ? texts2[comp.chunkIndex] : ""

                if !text1.isEmpty && !text2.isEmpty {
                    requests.append(SemanticComparisonRequest(
                        chunkIndex: comp.chunkIndex,
                        label1: m1.moveType,
                        label2: m2.moveType,
                        text1: text1,
                        text2: text2,
                        video1Id: fine.video1Id,
                        video2Id: fine.video2Id
                    ))
                }
            }

            // Call AI for semantic verification
            let verdicts = await callSemanticVerificationAI(requests: requests)

            // Update chunk comparisons with verdicts
            var updatedComparisons = fine.chunkComparisons
            for (index, var comp) in updatedComparisons.enumerated() {
                if let verdict = verdicts[comp.chunkIndex] {
                    comp.aiVerdict = verdict

                    // Compute adjusted score
                    if verdict.verdict == .same {
                        comp.adjustedScore = verdict.confidence == .high ? 0.95 : 0.7
                    } else {
                        comp.adjustedScore = 0.3  // AI says different
                    }
                    updatedComparisons[index] = comp
                }
            }

            let updated = FineComparisonResult(
                video1Id: fine.video1Id,
                video2Id: fine.video2Id,
                sequence1: fine.sequence1,
                sequence2: fine.sequence2,
                parentMatchScore: fine.parentMatchScore,
                fineScore: fine.fineScore,
                chunkComparisons: updatedComparisons
            )
            updatedResults.append(updated)
        }

        return updatedResults
    }

    /// Call AI to verify semantic similarity of chunk pairs
    private func callSemanticVerificationAI(
        requests: [SemanticComparisonRequest]
    ) async -> [Int: SemanticVerdict] {
        guard !requests.isEmpty else { return [:] }

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let systemPrompt = """
        You are analyzing pairs of transcript chunks from different videos.
        Each pair appears at the same position in their respective videos' argument structure.
        They have different specific labels but belong to the same rhetorical category.

        Your task: Determine if they are performing the SAME rhetorical function.

        Output ONLY valid JSON. No commentary.
        """

        var chunksDescription = ""
        for req in requests {
            chunksDescription += """

            ═══════════════════════════════════════════════════════════════
            CHUNK INDEX: \(req.chunkIndex)
            ═══════════════════════════════════════════════════════════════

            VIDEO A LABEL: \(req.label1.displayName) (\(req.label1.category.rawValue))
            VIDEO A TEXT (first 400 chars):
            \(String(req.text1.prefix(400)))

            VIDEO B LABEL: \(req.label2.displayName) (\(req.label2.category.rawValue))
            VIDEO B TEXT (first 400 chars):
            \(String(req.text2.prefix(400)))

            """
        }

        let userPrompt = """
        Compare these chunk pairs and determine if they perform the SAME rhetorical function:

        \(chunksDescription)

        For each chunk index, output:
        {
          "comparisons": [
            {
              "chunkIndex": 0,
              "verdict": "SAME" or "DIFFERENT",
              "sharedFunction": "description if SAME, null if DIFFERENT",
              "confidence": "HIGH" or "MEDIUM" or "LOW",
              "reasoning": "brief explanation"
            }
          ]
        }

        SAME means: Both chunks are doing essentially the same argumentative work,
        even if one uses case studies and the other uses statistics.

        DIFFERENT means: The chunks are doing fundamentally different rhetorical moves.
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": 0.1, "max_tokens": 2000]
        )

        return parseSemanticResponse(response)
    }

    private func parseSemanticResponse(_ response: String) -> [Int: SemanticVerdict] {
        var results: [Int: SemanticVerdict] = [:]

        let jsonString = extractJSON(from: response)
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return results
        }

        struct SemanticBatchResponse: Codable {
            let comparisons: [SemanticComparisonResponse]
        }

        do {
            let parsed = try JSONDecoder().decode(SemanticBatchResponse.self, from: data)
            for comp in parsed.comparisons {
                if let verdict = comp.toVerdict() {
                    results[comp.chunkIndex] = verdict
                }
            }
        } catch {
            print("⚠️ Failed to parse semantic response: \(error)")
        }

        return results
    }

    /// Compute final adjusted score after Stage 3
    private func computeAdjustedScore(for fine: FineComparisonResult) -> Double {
        let totalScore = fine.chunkComparisons.reduce(0.0) { $0 + $1.finalScore }
        return fine.chunkComparisons.isEmpty ? 0.0 : totalScore / Double(fine.chunkComparisons.count)
    }

    // MARK: - Levenshtein Distance

    /// Levenshtein for parent categories
    private func levenshteinDistanceCategories(_ s1: [RhetoricalCategory], _ s2: [RhetoricalCategory]) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    /// Calculate Levenshtein edit distance between two move sequences
    private func levenshteinDistance(_ s1: [RhetoricalMoveType], _ s2: [RhetoricalMoveType]) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Needleman-Wunsch Alignment

    /// Align two move sequences using Needleman-Wunsch algorithm
    private func needlemanWunschAlign(
        _ moves1: [RhetoricalMove],
        _ moves2: [RhetoricalMove]
    ) -> [AlignedMovePair] {
        let m = moves1.count
        let n = moves2.count

        // Scoring parameters
        let matchScore = 2
        let mismatchPenalty = -1
        let gapPenalty = -2

        // Initialize score matrix
        var score = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { score[i][0] = i * gapPenalty }
        for j in 0...n { score[0][j] = j * gapPenalty }

        // Fill score matrix
        for i in 1...m {
            for j in 1...n {
                let match = score[i - 1][j - 1] + (moves1[i - 1].moveType == moves2[j - 1].moveType ? matchScore : mismatchPenalty)
                let delete = score[i - 1][j] + gapPenalty
                let insert = score[i][j - 1] + gapPenalty
                score[i][j] = max(match, delete, insert)
            }
        }

        // Traceback to build alignment
        var alignment: [AlignedMovePair] = []
        var i = m
        var j = n
        var position = max(m, n) - 1

        while i > 0 || j > 0 {
            let current = i > 0 && j > 0 ? score[i][j] : Int.min
            let diagonal = i > 0 && j > 0 ? score[i - 1][j - 1] : Int.min
            let up = i > 0 ? score[i - 1][j] : Int.min
            let left = j > 0 ? score[i][j - 1] : Int.min

            let matchVal = moves1.indices.contains(i - 1) && moves2.indices.contains(j - 1) && moves1[i - 1].moveType == moves2[j - 1].moveType ? matchScore : mismatchPenalty

            if i > 0 && j > 0 && current == diagonal + matchVal {
                // Match or mismatch
                let pair = AlignedMovePair(
                    position: position,
                    move1: moves1[i - 1],
                    move2: moves2[j - 1]
                )
                alignment.append(pair)
                i -= 1
                j -= 1
            } else if i > 0 && current == up + gapPenalty {
                // Gap in sequence 2
                let pair = AlignedMovePair(
                    position: position,
                    move1: moves1[i - 1],
                    move2: nil
                )
                alignment.append(pair)
                i -= 1
            } else {
                // Gap in sequence 1
                let pair = AlignedMovePair(
                    position: position,
                    move1: nil,
                    move2: moves2[j - 1]
                )
                alignment.append(pair)
                j -= 1
            }
            position -= 1
        }

        // Reverse to get correct order
        return alignment.reversed()
    }
}

// MARK: - Errors

enum RhetoricalMoveError: LocalizedError {
    case noChunks
    case invalidResponse(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noChunks:
            return "Video has no chunks to analyze"
        case .invalidResponse(let msg):
            return "Invalid AI response: \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}
