//
//  DonorLibraryA2Service.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/12/26.
//

import Foundation
import FirebaseFirestore

// MARK: - A2: Slot Annotation Service (v2 — Phrase-Level)

/// Annotates creator sentences with phrase-level slot roles, deterministic hints,
/// and sentence function labels. Derives slot_sequence and slot_signature from phrases.
/// Runs on first 2 sections of each video (bootstrap scope).
@MainActor
class DonorLibraryA2Service: ObservableObject {
    static let shared = DonorLibraryA2Service()

    private let db = Firestore.firestore()
    private let collectionName = "creator_sentences"
    private let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress = ""
    @Published var currentVideoTitle = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    // MARK: - Run Slot Annotation

    /// Run A2 slot annotation on section 1 of any video with a rhetorical sequence.
    func runSlotAnnotation(videos: [YouTubeVideo], limit: Int? = nil) async {
        let eligible = videos.filter { video in
            video.hasRhetoricalSequence &&
            video.donorLibraryStatus?.a2Complete != true &&
            video.hasTranscript
        }

        let toProcess = limit.map { Array(eligible.prefix($0)) } ?? eligible
        guard !toProcess.isEmpty else {
            progress = "No eligible videos"
            return
        }

        isRunning = true
        completedVideos = 0
        totalVideos = toProcess.count
        progress = "Processing 0/\(totalVideos) videos"
        perVideoProgress = [:]

        for video in toProcess {
            currentVideoTitle = video.title
            perVideoProgress[video.videoId] = "Annotating..."

            do {
                let sentences = try await annotateVideo(video)
                try await saveSentences(sentences)
                try await markA2Complete(videoId: video.videoId, sentenceCount: sentences.count)
                completedVideos += 1
                progress = "Processing \(completedVideos)/\(totalVideos) videos"
                perVideoProgress[video.videoId] = "\(sentences.count) sentences"
            } catch {
                perVideoProgress[video.videoId] = "Error: \(error.localizedDescription)"
            }
        }

        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - Annotate Single Video

    private func annotateVideo(_ video: YouTubeVideo) async throws -> [CreatorSentence] {
        guard let sequence = video.rhetoricalSequence,
              let transcript = video.transcript else {
            throw DonorLibraryError.missingData("No rhetorical sequence or transcript")
        }

        let allSentences = SentenceParser.parse(transcript)
        guard !allSentences.isEmpty else {
            throw DonorLibraryError.missingData("No sentences parsed from transcript")
        }

        // Scene Set pos 1 only
        let firstTwoMoves = Array(sequence.moves.prefix(1))
        var creatorSentences: [CreatorSentence] = []

        for (sectionIdx, move) in firstTwoMoves.enumerated() {
            let startIdx = move.startSentence ?? 0
            let endIdx = move.endSentence ?? min(startIdx + 20, allSentences.count - 1)

            guard startIdx < allSentences.count else { continue }
            let clampedEnd = min(endIdx, allSentences.count - 1)
            let sectionSentences = Array(allSentences[startIdx...clampedEnd])

            guard !sectionSentences.isEmpty else { continue }

            perVideoProgress[video.videoId] = "Section 1 (\(sectionSentences.count) sentences)"

            // Strip parenthetical stage directions before LLM sees them
            // Filter out empty strings that result from fully-parenthetical sentences
            let strippedSentences = sectionSentences.map { DeterministicHints.stripParentheticals($0) }
            var cleanedSentences: [String] = []
            var cleanedToOriginalIdx: [Int] = []
            for (i, s) in strippedSentences.enumerated() {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    cleanedSentences.append(trimmed)
                    cleanedToOriginalIdx.append(i)
                }
            }

            guard !cleanedSentences.isEmpty else { continue }

            // Compute deterministic hints on cleaned text
            let hintsPerSentence = cleanedSentences.map { DeterministicHints.compute(for: $0) }

            let annotations = try await callSlotAnnotation(
                sentences: cleanedSentences,
                hints: hintsPerSentence,
                moveType: move.moveType.rawValue,
                category: move.moveType.category.rawValue
            )

            for (sentenceIdx, annotation) in annotations.enumerated() {
                let originalIdx = cleanedToOriginalIdx[sentenceIdx]
                let globalIdx = startIdx + originalIdx
                guard globalIdx <= clampedEnd else { break }

                let sentence = CreatorSentence(
                    id: "\(video.videoId)_\(sectionIdx)_\(sentenceIdx)",
                    videoId: video.videoId,
                    channelId: video.channelId,
                    sectionIndex: sectionIdx,
                    sentenceIndex: sentenceIdx,
                    moveType: move.moveType.rawValue,
                    sectionCategory: move.moveType.category.rawValue,
                    rawText: sectionSentences[originalIdx],
                    slotSequence: annotation.slotSequence,
                    slotSignature: annotation.slotSequence.joined(separator: "|"),
                    clauseCount: annotation.clauseCount,
                    wordCount: annotation.wordCount,
                    isQuestion: annotation.isQuestion,
                    isFragment: annotation.isFragment,
                    hasDirectAddress: annotation.hasDirectAddress,
                    openingPattern: annotation.openingPattern,
                    phrases: annotation.phrases,
                    sentenceFunction: annotation.sentenceFunction,
                    deterministicHints: annotation.deterministicHints,
                    hintMismatches: annotation.hintMismatches,
                    embedding: nil,
                    prevSlotSignature: nil,
                    nextSlotSignature: nil,
                    createdAt: Date()
                )
                creatorSentences.append(sentence)
            }
        }

        // Fill in neighbor signatures
        for i in 0..<creatorSentences.count {
            let prev = i > 0 ? creatorSentences[i - 1].slotSignature : nil
            let next = (i + 1 < creatorSentences.count) ? creatorSentences[i + 1].slotSignature : nil
            let s = creatorSentences[i]

            creatorSentences[i] = CreatorSentence(
                id: s.id, videoId: s.videoId, channelId: s.channelId,
                sectionIndex: s.sectionIndex, sentenceIndex: s.sentenceIndex,
                moveType: s.moveType, sectionCategory: s.sectionCategory,
                rawText: s.rawText, slotSequence: s.slotSequence,
                slotSignature: s.slotSignature, clauseCount: s.clauseCount,
                wordCount: s.wordCount, isQuestion: s.isQuestion,
                isFragment: s.isFragment, hasDirectAddress: s.hasDirectAddress,
                openingPattern: s.openingPattern,
                phrases: s.phrases, sentenceFunction: s.sentenceFunction,
                deterministicHints: s.deterministicHints, hintMismatches: s.hintMismatches,
                embedding: s.embedding,
                prevSlotSignature: prev,
                nextSlotSignature: next,
                createdAt: s.createdAt
            )
        }

        return creatorSentences
    }

    // MARK: - LLM Call: Slot Annotation (Prompt 7.2 — Phrase-Level)

    // ──────────────────────────────────────────────────────────────────
    // PROMPT HISTORY
    //
    // v7.3 (REVERTED — made things worse)
    //
    // Added PHRASE SEGMENTATION RULES before slot definitions to fix
    // over-segmentation and ~29% "other" rate. Rules told the LLM to
    // keep grammatical units together (noun phrases, verb phrases,
    // prepositional phrases) and target 3-6 phrases per sentence.
    //
    // RESULT: v7.2 produced 91% signature match on olive oil with
    // consistent phrase labeling across 5 runs. v7.3 made it worse
    // everywhere that matters.
    //
    // WHY v7.2 WINS: The over-segmentation (28.7% "other") is a
    // phrase-level cosmetic issue that doesn't break signatures. The
    // signatures were consistent because the meaningful phrases
    // (temporal_marker, geographic_location, actor_reference,
    // narrative_action) were labeled correctly and consistently —
    // the "other" fragments were just noise between them. When you
    // derive slot_signature, the "other" entries are present but
    // they're consistently present, so signatures still match.
    //
    // LESSON: If you want to clean up "other" for display or to
    // tighten signatures, do it in post-processing code after the
    // LLM returns: merge any phrase labeled "other" into the adjacent
    // phrase before or after it. Don't touch the prompt. The prompt
    // is working — let it do what it does naturally and clean up
    // the edges in code.
    //
    // v7.3 PROMPT (kept for reference):
    //   Opening: "You annotate creator transcript sentences by
    //   splitting them into grammatical phrases, then labeling each
    //   phrase with a content slot role."
    //
    //   PHRASE SEGMENTATION RULES:
    //   Each phrase must be a complete grammatical unit. Follow these rules:
    //   - A subject noun phrase stays together: "The police" not "The" + "police"
    //   - A verb phrase stays together with its object: "were spying on an organized crime network" not "were spying on" + "an organized crime network"
    //   - A prepositional phrase stays together with what it modifies: "in southern Italy" not "in" + "southern Italy"
    //   - Conjunctions attach to the clause they introduce: "and found that the trucks were loaded" not "and" + "found that..."
    //   - Connective words like "so that", "and then", "but then" attach to the following clause, not standalone
    //   - Target 3-6 phrases per sentence. If you have more than 6, you are splitting too finely.
    // ──────────────────────────────────────────────────────────────────

    /// Builds the system + user prompts for slot annotation. Shared by both the regular and debug call paths.
    private func buildSlotAnnotationPrompts(
        sentences: [String],
        hints: [SentenceHints],
        moveType: String,
        category: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let systemPrompt = """
        You annotate creator transcript sentences by labeling individual phrases with content slot roles.

        19 slot roles:
        - geographic_location: place references ("in southern Iowa", "behind a gate in New Jersey")
        - visual_detail: visual descriptions ("stacked three high", "a gravel road lined with oaks")
        - quantitative_claim: numbers/data ("64 deer per square mile", "forty-seven containers")
        - temporal_marker: time references ("this season", "for years", "last October")
        - actor_reference: people/entities ("most hunters", "the landowner", "I")
        - contradiction: opposing claims ("but something didn't add up", "actually isn't")
        - sensory_detail: non-visual senses ("the hum of the motor", "pitch black timber")
        - rhetorical_question: questions to audience ("So why does this matter?")
        - evaluative_claim: judgments ("the single most overrated thing")
        - pivot_phrase: structural turns ("But here's the thing", "And this is where it gets strange")
        - direct_address: speaking to viewer ("you've probably driven past one")
        - narrative_action: actions taken ("I pulled up the data", "the drone flew over")
        - abstract_framing: conceptual framing ("This changes everything", "Nobody talks about this")
        - comparison: comparing things ("three times more than", "unlike traditional methods")
        - empty_connector: minimal connectives ("And so", "But" standalone)
        - factual_relay: bare factual statements, chronological narration, neutral description without judgment or framing ("The olive oil is stored in steel tanks", "The CIA then drives their prisoners 20 minutes from this little airport")
        - reaction_beat: interjections, verbal reactions, performative emotional cues ("Oh,", "Wow.", "Right.", "Yeah.", "Man.")
        - visual_anchor: deictic references pointing to on-screen visuals ("This.", "Look at that.", "Here.", "Check this out.")
        - other: doesn't fit above categories

        LABELING GUIDE — IS vs IS NOT:

        geographic_location
          IS: "in southern Italy", "from Louisiana", "in an Oregon hotel"
          IS NOT: "across the world" (too vague), "in attendance" (not a place)

        quantitative_claim
          IS: "23,000 liters per week", "8 million euros a year", "hundreds of dollars"
          IS NOT: "government welfare programs" (no number), "these corporations" (no number)

        narrative_action
          IS: "were spying on", "caught wind of this", "secretly filmed"
          AMBIGUOUS: "were selling around 23,000 liters" — could be narrative_action or quantitative_claim depending on emphasis; both are valid

        evaluative_claim
          IS: "is really hard to make", "may be disturbing", "it's really healthy and delicious"
          IS NOT: "This changes everything" (abstract_framing, not evaluation)

        temporal_marker
          IS: "Last fall", "A couple years ago", "a few months later"
          IS NOT: "At times" (frequency), "Sometimes" (frequency), "Then" (sequencer)

        actor_reference
          IS: "most hunters", "the landowner", "the police", "I"
          IS NOT: "you" (direct_address), "it" (pronoun, not actor)

        pivot_phrase
          IS: "But here's the thing", "And this is where it gets strange"
          IS NOT: "But they also..." (contrast continuation, likely contradiction)

        abstract_framing
          IS: "This changes everything", "Nobody talks about this"
          IS NOT: "is really hard to make" (evaluative_claim — judgment, not framing)

        factual_relay
          IS: "The olive oil is stored in steel tanks", "It was a dense metal", "The electrons are moving nearly the speed of light"
          IS NOT: "The single most overrated thing" (evaluative_claim), "This changes everything" (abstract_framing)

        reaction_beat
          IS: "Oh,", "Wow.", "Right.", "Yeah.", "Man.", "Whoa."
          IS NOT: "Oh that's interesting" (has a clause — evaluative_claim)

        visual_anchor
          IS: "This.", "Look at that.", "Here.", "Check this out."
          IS NOT: "This is the biggest problem" (abstract_framing — has full clause)

        Sentence function labels (pick the best match for the sentence's rhetorical purpose):
        scene_set, establish_assumption, introduce_contradiction, deliver_evidence, pose_question, direct_address, transition_bridge, evaluative_judgment, narrative_action, context_anchor, reveal_payoff, other

        Each sentence includes [hints] — deterministic flags computed from the text. Use them to confirm your annotations. If a hint says hasTemporalMarker, ensure you label the temporal phrase. If a hint says hasContrastMarker, look for a contradiction or pivot_phrase. If a hint says isReactionBeat, label the sentence as reaction_beat. If a hint says isVisualAnchor, label the sentence as visual_anchor.

        Return ONLY valid JSON. No markdown, no explanation.
        """

        let numberedSentences = sentences.enumerated().map { idx, s in
            let h = hints[idx]
            let hintLabels = h.activeHintLabels
            let hintStr = hintLabels.isEmpty ? "none" : hintLabels.joined(separator: ", ")
            return "\(idx + 1). \"\(s)\"\n   [hints: \(hintStr)]"
        }.joined(separator: "\n")

        let userPrompt = """
        Section move: \(moveType) | Category: \(category)

        Sentences:
        \(numberedSentences)

        For each sentence, return a JSON array with objects containing:
        {
          "idx": <1-based index>,
          "phrases": [
            {"text": "<exact phrase from sentence>", "role": "<slot role>"},
            ...
          ],
          "clause_count": <int>,
          "word_count": <int>,
          "is_question": <bool>,
          "is_fragment": <bool>,
          "has_direct_address": <bool>,
          "opening_pattern": "<first 2-3 words>",
          "sentence_function": "<one of the function labels>"
        }

        Rules:
        - Each phrase should be a contiguous substring from the original sentence
        - Phrases should cover the full sentence (no gaps)
        - The role ordering in phrases reflects the natural order in the sentence
        - Use the hints to guide your labeling — confirm what the hints detected

        Return ONLY the JSON array.
        """

        return (systemPrompt, userPrompt)
    }

    func callSlotAnnotation(
        sentences: [String],
        hints: [SentenceHints],
        moveType: String,
        category: String,
        temperature: Double = 0.1
    ) async throws -> [SlotAnnotationResult] {
        let prompts = buildSlotAnnotationPrompts(
            sentences: sentences, hints: hints, moveType: moveType, category: category
        )

        let response = await adapter.generate_response(
            prompt: prompts.userPrompt,
            promptBackgroundInfo: prompts.systemPrompt,
            params: ["temperature": temperature, "max_tokens": 16000]
        )

        return parseSlotAnnotations(response, hints: hints, expectedCount: sentences.count)
    }

    /// Debug variant — returns parsed results + raw prompt/response for inspection
    struct SlotAnnotationDebugResult {
        let results: [SlotAnnotationResult]
        let systemPrompt: String
        let userPrompt: String
        let rawResponse: String
        let parseSucceeded: Bool
    }

    func callSlotAnnotationWithDebug(
        sentences: [String],
        hints: [SentenceHints],
        moveType: String,
        category: String,
        temperature: Double = 0.1
    ) async throws -> SlotAnnotationDebugResult {
        let prompts = buildSlotAnnotationPrompts(
            sentences: sentences, hints: hints, moveType: moveType, category: category
        )

        let response = await adapter.generate_response(
            prompt: prompts.userPrompt,
            promptBackgroundInfo: prompts.systemPrompt,
            params: ["temperature": temperature, "max_tokens": 16000]
        )

        let parsed = parseSlotAnnotations(response, hints: hints, expectedCount: sentences.count)

        return SlotAnnotationDebugResult(
            results: parsed,
            systemPrompt: prompts.systemPrompt,
            userPrompt: prompts.userPrompt,
            rawResponse: response,
            parseSucceeded: !parsed.isEmpty
        )
    }

    // MARK: - Parse LLM Response (Phrase-Level)

    private func parseSlotAnnotations(
        _ response: String,
        hints: [SentenceHints],
        expectedCount: Int
    ) -> [SlotAnnotationResult] {
        var cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON array — strip any preamble text before '[' and trailing text after ']'
        if let firstBracket = cleaned.firstIndex(of: "["),
           let lastBracket = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[firstBracket...lastBracket])
        }

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Fallback: create default annotations
            return (0..<expectedCount).map { idx in
                let h = idx < hints.count ? hints[idx] : SentenceHints()
                return SlotAnnotationResult(
                    phrases: [SentencePhrase(text: "", role: "other")],
                    slotSequence: ["other"],
                    sentenceFunction: "other",
                    clauseCount: 1,
                    wordCount: 10,
                    isQuestion: false,
                    isFragment: false,
                    hasDirectAddress: false,
                    openingPattern: "",
                    deterministicHints: h.activeHintLabels,
                    hintMismatches: []
                )
            }
        }

        return jsonArray.enumerated().map { idx, dict in
            // Parse phrases
            let rawPhrases = (dict["phrases"] as? [[String: Any]]) ?? []
            let phrases: [SentencePhrase] = rawPhrases.map { p in
                let text = p["text"] as? String ?? ""
                let role = p["role"] as? String ?? "other"
                let validRole = SlotType(rawValue: role) != nil ? role : "other"
                return SentencePhrase(text: text, role: validRole)
            }

            // Derive slot_sequence from phrases
            let slotSequence = phrases.isEmpty ? ["other"] : phrases.map { $0.role }

            // Parse sentence_function
            let rawFunction = dict["sentence_function"] as? String ?? "other"
            let sentenceFunction = SentenceFunction(rawValue: rawFunction) != nil ? rawFunction : "other"

            // Get hints for cross-validation
            let h = idx < hints.count ? hints[idx] : SentenceHints()
            let hintLabels = h.activeHintLabels
            let mismatches = DeterministicHints.crossValidate(hints: h, phraseRoles: Set(slotSequence))

            return SlotAnnotationResult(
                phrases: phrases,
                slotSequence: slotSequence,
                sentenceFunction: sentenceFunction,
                clauseCount: dict["clause_count"] as? Int ?? 1,
                wordCount: dict["word_count"] as? Int ?? 10,
                isQuestion: dict["is_question"] as? Bool ?? false,
                isFragment: dict["is_fragment"] as? Bool ?? false,
                hasDirectAddress: dict["has_direct_address"] as? Bool ?? false,
                openingPattern: dict["opening_pattern"] as? String ?? "",
                deterministicHints: hintLabels,
                hintMismatches: mismatches
            )
        }
    }

    // MARK: - Firebase Save

    private func saveSentences(_ sentences: [CreatorSentence]) async throws {
        let batchSize = 400
        for startIdx in stride(from: 0, to: sentences.count, by: batchSize) {
            let endIdx = min(startIdx + batchSize, sentences.count)
            let batch = db.batch()

            for sentence in sentences[startIdx..<endIdx] {
                let docRef = db.collection(collectionName).document(sentence.id)
                try batch.setData(from: sentence, forDocument: docRef)
            }

            try await batch.commit()
        }
    }

    private func markA2Complete(videoId: String, sentenceCount: Int) async throws {
        let docRef = db.collection("youtube_videos").document(videoId)

        let snapshot = try await docRef.getDocument()
        var status = DonorLibraryStatus()
        if let existing = snapshot.data()?["donorLibraryStatus"] as? [String: Any] {
            status.a2Complete = true
            status.a3Complete = existing["a3Complete"] as? Bool ?? false
            status.a4Complete = existing["a4Complete"] as? Bool ?? false
            status.a5Complete = existing["a5Complete"] as? Bool ?? false
            status.sentenceCount = sentenceCount
            status.lastUpdated = Date()
        } else {
            status.a2Complete = true
            status.sentenceCount = sentenceCount
            status.lastUpdated = Date()
        }

        try await docRef.setData([
            "donorLibraryStatus": [
                "a2Complete": status.a2Complete,
                "a3Complete": status.a3Complete,
                "a4Complete": status.a4Complete,
                "a5Complete": status.a5Complete,
                "sentenceCount": status.sentenceCount,
                "lastUpdated": Timestamp(date: Date())
            ]
        ], merge: true)
    }

    // MARK: - Query

    func loadSentences(forVideoId videoId: String) async throws -> [CreatorSentence] {
        let snapshot = try await db.collection(collectionName)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: CreatorSentence.self)
        }
    }

    func loadSentences(forChannelId channelId: String) async throws -> [CreatorSentence] {
        let snapshot = try await db.collection(collectionName)
            .whereField("channelId", isEqualTo: channelId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: CreatorSentence.self)
        }
    }
}

// MARK: - Slot Annotation Result

struct SlotAnnotationResult {
    let phrases: [SentencePhrase]
    let slotSequence: [String]          // Derived from phrases
    let sentenceFunction: String
    let clauseCount: Int
    let wordCount: Int
    let isQuestion: Bool
    let isFragment: Bool
    let hasDirectAddress: Bool
    let openingPattern: String
    let deterministicHints: [String]
    let hintMismatches: [String]
}

// MARK: - Deterministic Hints

struct SentenceHints {
    var hasNumber = false
    var endsWithQuestion = false
    var hasContrastMarker = false
    var hasTemporalMarker = false
    var hasFirstPerson = false
    var hasSecondPerson = false
    var isReactionBeat = false
    var isVisualAnchor = false

    var activeHintLabels: [String] {
        var labels: [String] = []
        if hasNumber { labels.append("hasNumber") }
        if endsWithQuestion { labels.append("endsWithQuestion") }
        if hasContrastMarker { labels.append("hasContrastMarker") }
        if hasTemporalMarker { labels.append("hasTemporalMarker") }
        if hasFirstPerson { labels.append("hasFirstPerson") }
        if hasSecondPerson { labels.append("hasSecondPerson") }
        if isReactionBeat { labels.append("isReactionBeat") }
        if isVisualAnchor { labels.append("isVisualAnchor") }
        return labels
    }
}

enum DeterministicHints {

    /// Strip parenthetical stage directions like "(Reporter speaking Italian) -" before LLM annotation.
    static func stripParentheticals(_ sentence: String) -> String {
        sentence.replacingOccurrences(
            of: #"\([^)]*\)\s*-?\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Compute deterministic flags for a single sentence. Zero LLM cost.
    static func compute(for sentence: String) -> SentenceHints {
        let lower = sentence.lowercased()
        var hints = SentenceHints()

        // hasNumber: digits or common number words
        let numberPattern = #"(\d+|(?:^|\s)(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion|dozen|half)(?:\s|$|[,;.!?]))"#
        hints.hasNumber = lower.range(of: numberPattern, options: .regularExpression) != nil

        // endsWithQuestion
        hints.endsWithQuestion = sentence.trimmingCharacters(in: .whitespaces).hasSuffix("?")

        // hasContrastMarker
        let contrastPattern = #"\b(but|however|yet|actually|though|although|nevertheless|nonetheless|instead|rather|on the other hand)\b"#
        hints.hasContrastMarker = lower.range(of: contrastPattern, options: .regularExpression) != nil

        // hasTemporalMarker — tight: explicit years, "X ago/later", "last/next/this + time unit", month names, "per week/year"
        let temporalPattern = #"(\b\d{4}\b|\byears?\s+ago\b|\bmonths?\s+ago\b|\bweeks?\s+ago\b|\bdays?\s+ago\b|\ba\s+couple\s+(years?|months?|weeks?|days?)\b|\ba\s+few\s+(years?|months?|weeks?|days?)\b|\b(last|next|this)\s+(season|year|month|week|fall|spring|summer|winter|january|february|march|april|may|june|july|august|september|october|november|december|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\b(yesterday|tomorrow)\b|\b(january|february|march|april|may|june|july|august|september|october|november|december)\b|\bper\s+(week|month|year|day)\b|\ba\s+(year|month|week|day)\b|\b(years?|months?|weeks?|days?)\s+later\b|\brecently\b|\bearlier\s+that\b)"#
        hints.hasTemporalMarker = lower.range(of: temporalPattern, options: .regularExpression) != nil

        // hasFirstPerson
        let firstPersonPattern = #"\b(I|me|my|mine|we|us|our|ours|myself|ourselves)\b"#
        hints.hasFirstPerson = sentence.range(of: firstPersonPattern, options: .regularExpression) != nil

        // hasSecondPerson
        let secondPersonPattern = #"\b(you|your|yours|yourself|yourselves)\b"#
        hints.hasSecondPerson = lower.range(of: secondPersonPattern, options: .regularExpression) != nil

        // isReactionBeat: standalone interjections / performative reactions
        let reactionPattern = #"^(oh|wow|yeah|yep|nope|right|sure|okay|ok|man|dude|hmm|huh|ah|whoa|no|yes|well|check)[,!.]*\s*$"#
        hints.isReactionBeat = lower.range(of: reactionPattern, options: .regularExpression) != nil

        // isVisualAnchor: deictic standalone references pointing to visuals
        let anchorPattern = #"^(this|that|these|those|here|there|look at (this|that)|check this out)[.!]*\s*$"#
        hints.isVisualAnchor = lower.range(of: anchorPattern, options: .regularExpression) != nil

        return hints
    }

    /// Cross-validate: check if deterministic hints are reflected in the LLM's phrase roles.
    /// Returns list of mismatches (hint was true but no corresponding role found).
    static func crossValidate(hints: SentenceHints, phraseRoles: Set<String>) -> [String] {
        var mismatches: [String] = []

        if hints.hasTemporalMarker && !phraseRoles.contains("temporal_marker") {
            mismatches.append("hasTemporalMarker but no temporal_marker phrase")
        }
        if hints.hasContrastMarker &&
            !phraseRoles.contains("contradiction") &&
            !phraseRoles.contains("pivot_phrase") {
            mismatches.append("hasContrastMarker but no contradiction or pivot_phrase")
        }
        if hints.endsWithQuestion && !phraseRoles.contains("rhetorical_question") {
            // Not always a mismatch — could be a narrative question rather than rhetorical
            // Only flag if no question-type role at all
            if !phraseRoles.contains("direct_address") {
                mismatches.append("endsWithQuestion but no rhetorical_question phrase")
            }
        }
        if hints.hasSecondPerson && !phraseRoles.contains("direct_address") {
            mismatches.append("hasSecondPerson but no direct_address phrase")
        }
        if hints.hasNumber && !phraseRoles.contains("quantitative_claim") {
            // Numbers appear in many contexts, so this is a soft flag
            // Only flag if the number pattern is strong (standalone numbers, not embedded)
        }
        if hints.isReactionBeat && !phraseRoles.contains("reaction_beat") {
            mismatches.append("isReactionBeat but no reaction_beat phrase")
        }
        if hints.isVisualAnchor && !phraseRoles.contains("visual_anchor") {
            mismatches.append("isVisualAnchor but no visual_anchor phrase")
        }

        return mismatches
    }
}

// MARK: - Errors

enum DonorLibraryError: LocalizedError {
    case missingData(String)
    case llmError(String)
    case firebaseError(String)

    var errorDescription: String? {
        switch self {
        case .missingData(let msg): return "Missing data: \(msg)"
        case .llmError(let msg): return "LLM error: \(msg)"
        case .firebaseError(let msg): return "Firebase error: \(msg)"
        }
    }
}
