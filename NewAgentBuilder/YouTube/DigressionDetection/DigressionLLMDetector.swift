import Foundation

/// Single-prompt LLM digression detector
/// Sends the full numbered transcript to Claude, gets back digression sentence ranges + types
class DigressionLLMDetector {

    static let shared = DigressionLLMDetector()

    private init() {}

    // MARK: - Main Detection

    func detectDigressions(
        sentences: [SentenceTelemetry],
        enabledTypes: Set<DigressionType>,
        temperature: Double,
        onProgress: ((String) -> Void)? = nil
    ) async -> [DigressionAnnotation] {
        guard !sentences.isEmpty else { return [] }

        onProgress?("Sending \(sentences.count) sentences to Claude...")

        let numberedTranscript = sentences.map { s in
            "[\(s.sentenceIndex)] (\(s.stance)|\(s.perspective)) \(s.text)"
        }.joined(separator: "\n")

        let systemPrompt = buildSystemPrompt(enabledTypes: enabledTypes)
        let userPrompt = buildUserPrompt(
            numberedTranscript: numberedTranscript,
            sentenceCount: sentences.count,
            enabledTypes: enabledTypes
        )

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 4096]
        )

        onProgress?("Parsing LLM response...")

        let parsed = parseResponse(response, sentences: sentences)

        #if DEBUG
        print(generateDebugReport(
            rawResponse: response,
            parsed: parsed,
            sentenceCount: sentences.count
        ))
        #endif

        return parsed
    }

    // MARK: - Prompt Building

//    private func buildSystemPrompt(enabledTypes: Set<DigressionType>) -> String {
//        """
//        You analyze YouTube video transcripts to find digressions — moments where the narrator \
//        temporarily leaves the main narrative or argument thread, then returns to it.
//
//        A digression is NOT part of the argument. It PAUSES the argument. The key test: if you \
//        removed these sentences, would the surrounding content still flow logically? If yes, \
//        it's a digression.
//
//        There are 7 types:
//
//        PERSONAL_ASIDE — The creator inserts a personal experience triggered by something in \
//        the content. They connect themselves to what they're describing, then dismiss it and \
//        return. Often starts with "Wait a minute" or "Wait," and ends with "Anyway, that's \
//        beside the point" or similar dismissal.
//        Example: Narrator is describing drug tunnels → "Wait a minute. So I lived in Tijuana \
//        for two years when I was a Mormon missionary, and I actually lived right next to one \
//        of these tunnels. Whoa. Anyway, that's beside the point." → Returns to narrative.
//
//        SPONSOR_READ — A paid advertisement. Usually clearly marked ("this video is sponsored \
//        by") but sometimes transitioned into smoothly. The entire ad section is the digression, \
//        from entry to the return marker ("Alright, back to...").
//
//        META_COMMENTARY — The creator comments on the video itself — its style, production, \
//        or how the audience is receiving it. Not about the topic, about the video.
//        Example: "By the way, how are you liking the 3D style of this video? It's kind of new \
//        for us, we're deeply inspired by the YouTube channel Fern."
//
//        TANGENT — The creator drifts into a loosely related topic triggered by a detail they \
//        just mentioned. Distinguished from PERSONAL_ASIDE by not necessarily being about the \
//        creator's personal experience — it's an associative drift.
//        Example: Narrator mentions a Chevy Monte Carlo → "I don't know what year this one was, \
//        but this one from the seventies is super sick. The one from 2006 is like the most \
//        uninspiring vehicle I've ever seen."
//        Note: Tangents often have NO self-aware entry marker. The creator just drifts. Look for \
//        sudden topic shifts to loosely related subjects that last 2-5 sentences.
//
//        MORAL_CORRECTION — The creator pauses the narrative to insert their values. This happens \
//        when the narrative momentum risks making a villain seem admirable. The creator steps out \
//        of storytelling mode to say "but this person is actually bad."
//        Example: After describing El Chapo's Robin Hood image → "But don't be fooled. This guy \
//        was not a Robin Hood. His drug empire resulted in lots of death, and addiction and \
//        suffering."
//
//        SELF_PROMOTION — The creator promotes their own projects, community, or other content. \
//        NOT a paid sponsor — this is the creator's own stuff.
//        Example: "Also, did you know that we're reinventing journalism over at New Press? Go to \
//        newpress.com, give us your email."
//
//        FORESHADOWING_PLANT — The creator briefly breaks from narration to explicitly tell the \
//        audience that a detail will matter later. Usually 1-2 sentences.
//        Example: "He had houses all over Mexico and crucially, which will come in later in the \
//        story, all of his houses were rigged with secret trap doors and escape tunnels."
//
//        CRITICAL — What is NOT a digression:
//
//        - A personal story that IS the main content is not a PERSONAL_ASIDE. If the creator's \
//          experience is the evidence they're building, that's content.
//        - Rhetorical questions within the narrative ("Why couldn't they catch this guy?") advance \
//          the argument — not digressions.
//        - End-of-video CTAs ("Subscribe, like, comment") in the last 10% are standard closing, \
//          not digressions.
//        - A creator expressing emotion about the topic within the narrative flow ("I mean the \
//          guy's good") is voice, not a digression. It only becomes a MORAL_CORRECTION if they \
//          stop the narrative to deliver an evaluative judgment.
//        """
//    }
    
    private func buildSystemPrompt(enabledTypes: Set<DigressionType>) -> String {
            """
            You analyze YouTube video transcripts to find digressions — moments where the narrator \
            temporarily leaves the main narrative or argument thread, then returns to it.

            A digression is NOT part of the argument. It PAUSES the argument. The key test: if you \
            removed these sentences, would the surrounding content still flow logically? If yes, \
            it's a digression.

            There are 7 types:

            PERSONAL_ASIDE — The creator inserts a personal experience triggered by something in \
            the content. They connect themselves to what they're describing, then dismiss it and \
            return. Often starts with "Wait a minute" or "Wait," and ends with "Anyway, that's \
            beside the point" or similar dismissal.
            Example: Narrator is describing drug tunnels → "Wait a minute. So I lived in Tijuana \
            for two years when I was a Mormon missionary, and I actually lived right next to one \
            of these tunnels. Whoa. Anyway, that's beside the point." → Returns to narrative.

            SPONSOR_READ — A paid advertisement. Usually clearly marked ("this video is sponsored \
            by") but sometimes transitioned into smoothly. The entire ad section is the digression, \
            from entry to the return marker ("Alright, back to...").

            META_COMMENTARY — The creator comments on the video itself — its style, production, \
            or how the audience is receiving it. Not about the topic, about the video.
            Example: "By the way, how are you liking the 3D style of this video? It's kind of new \
            for us, we're deeply inspired by the YouTube channel Fern."

            TANGENT — The creator drifts into a loosely related topic triggered by a detail they \
            just mentioned. Distinguished from PERSONAL_ASIDE by not necessarily being about the \
            creator's personal experience — it's an associative drift.
            Example: Narrator mentions a Chevy Monte Carlo → "I don't know what year this one was, \
            but this one from the seventies is super sick. The one from 2006 is like the most \
            uninspiring vehicle I've ever seen."
            Note: Tangents often have NO self-aware entry marker. The creator just drifts. Look for \
            sudden topic shifts to loosely related subjects that last 2-5 sentences.

            MORAL_CORRECTION — The creator pauses the narrative to insert a value judgment that \
            INTERRUPTS the story without advancing it. This is a brief "hold on, let me be \
            responsible" moment — the creator breaks character from storyteller to say something \
            they feel obligated to say, then returns to the narrative.
            Example: Mid-story about a heist → "Now, I'm not condoning any of this. Crime is bad, \
            obviously." → Resumes heist story.
            NOT a moral correction: When the creator builds a case that reframes the audience's \
            understanding. If the evaluative passage introduces NEW information (death tolls, \
            corruption effects, consequences), changes how the audience should interpret what \
            came before, or sustains for 3+ sentences with evidence — that is argumentative \
            content (a reframe or revelation), not a digression. The test: does this passage \
            change what the audience KNOWS, or just what the creator FEELS? If it adds facts \
            or reframes understanding, it's content. If it's pure "I should say this is bad" \
            without new information, it's a moral correction.

            SELF_PROMOTION — The creator promotes their own projects, community, or other content. \
            NOT a paid sponsor — this is the creator's own stuff.
            Example: "Also, did you know that we're reinventing journalism over at New Press? Go to \
            newpress.com, give us your email."

            FORESHADOWING_PLANT — The creator explicitly tells the audience that a current detail \
            will matter later, using phrases like "which will come in later" or "remember this \
            for later" — BUT the sentence contains NO factual content beyond the flag itself.
            Example (IS a digression): "That was foreshadowing." or "Remember that, it'll be \
            important later."
            Example (NOT a digression): "He had houses all over Mexico and crucially, which will \
            come in later in the story, all of his houses were rigged with secret trap doors \
            and escape tunnels." — This sentence delivers factual information (houses had trap \
            doors and tunnels) that the audience needs to understand later events. The \
            foreshadowing flag ("which will come in later") is wrapped around real content. \
            Do NOT mark this as a digression.
            The test: if you strip the foreshadowing language ("which will come in later"), does \
            the sentence still contain information the audience needs? If yes, it is NOT a \
            digression — it's narrative content with a foreshadowing wrapper.

            CRITICAL — What is NOT a digression:

            - A personal story that IS the main content is not a PERSONAL_ASIDE. If the creator's \
              experience is the evidence they're building, that's content.
            - Rhetorical questions within the narrative ("Why couldn't they catch this guy?") advance \
              the argument — not digressions.
            - End-of-video CTAs ("Subscribe, like, comment") in the last 10% are standard closing, \
              not digressions.
            - A creator expressing emotion about the topic within the narrative flow ("I mean the \
              guy's good") is voice, not a digression. It only becomes a MORAL_CORRECTION if they \
              stop the narrative to deliver a value judgment that adds NO new information.
            - Evaluative passages that introduce new facts, reframe the audience's understanding, \
              or build an argument are NOT digressions even if they contain moral judgment. A \
              passage like "But don't be fooled. His drug empire resulted in lots of death and \
              addiction and suffering, contributing to corruption at every level" is a REFRAME — \
              it changes what the audience knows. That's content.
            - Sentences that contain factual information wrapped in foreshadowing language are NOT \
              digressions. Only mark FORESHADOWING_PLANT when the sentence is purely a meta-flag \
              with no informational payload.
            - Narrative callbacks or payoffs ("Unforgivable indeed. He escaped for the second time.") \
              are story beats, not meta-commentary. They land an earlier setup. That's structure, \
              not digression.
            """
        }

    private func buildUserPrompt(
        numberedTranscript: String,
        sentenceCount: Int,
        enabledTypes: Set<DigressionType>
    ) -> String {
        let typeList = enabledTypes
            .sorted { $0.priority < $1.priority }
            .map(\.rawValue)
            .joined(separator: ", ")

        return """
        Here is a YouTube video transcript with \(sentenceCount) sentences. Each sentence includes \
        [index] (stance|perspective) before the text. Find all digressions.

        For each digression, respond with exactly this format (one per line):
        DIGRESSION|\(typeList.contains(",") ? "type" : typeList)|startSentence|endSentence|brief description

        If no digressions are found, respond with:
        NO_DIGRESSIONS

        Types: \(typeList)

        Transcript:
        \(numberedTranscript)
        """
    }

    // MARK: - Response Parsing

    private func parseResponse(
        _ response: String,
        sentences: [SentenceTelemetry]
    ) -> [DigressionAnnotation] {
        let lines = response.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if lines.contains(where: { $0.contains("NO_DIGRESSIONS") }) {
            return []
        }

        var results: [DigressionAnnotation] = []

        for line in lines {
            guard line.hasPrefix("DIGRESSION|") || line.hasPrefix("DIGRESSION:") else { continue }

            if let annotation = parseLine(line, sentences: sentences) {
                results.append(annotation)
            }
        }

        return results.sorted { $0.startSentence < $1.startSentence }
    }

    private func parseLine(
        _ line: String,
        sentences: [SentenceTelemetry]
    ) -> DigressionAnnotation? {
        // Handle both DIGRESSION|type|start|end|brief and DIGRESSION: type|start|end|brief
        let content: String
        if line.hasPrefix("DIGRESSION|") {
            content = String(line.dropFirst("DIGRESSION|".count))
        } else if line.hasPrefix("DIGRESSION:") {
            content = String(line.dropFirst("DIGRESSION:".count)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }

        let parts = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 4 else { return nil }

        let typeStr = parts[0]
        let startStr = parts[1]
        let endStr = parts[2]
        let brief = parts.count >= 4 ? parts[3] : ""

        guard let type = DigressionType(rawValue: typeStr) else { return nil }
        guard let start = Int(startStr), let end = Int(endStr) else { return nil }

        let clampedStart = max(0, min(start, sentences.count - 1))
        let clampedEnd = max(clampedStart, min(end, sentences.count - 1))

        let digressionSentences = Array(sentences[clampedStart...clampedEnd])
        let hasCTA = digressionSentences.contains { $0.isCallToAction }
        let perspectives = Set(digressionSentences.map(\.perspective))
        let stances = Set(digressionSentences.map(\.stance))

        return DigressionAnnotation(
            startSentence: clampedStart,
            endSentence: clampedEnd,
            entryMarker: "LLM detected",
            exitMarker: "LLM detected (end s\(clampedEnd))",
            type: type,
            confidence: 0.7,
            detectionMethod: .llm,
            briefContent: brief.isEmpty ? nil : brief,
            hasCTA: hasCTA,
            perspectiveShift: perspectives.count > 1,
            stanceShift: stances.count > 1
        )
    }

    // MARK: - Debug Report

    private func generateDebugReport(
        rawResponse: String,
        parsed: [DigressionAnnotation],
        sentenceCount: Int
    ) -> String {
        """
        ════════════════════════════════════════════════════════════════
        LLM DIGRESSION DETECTION DEBUG REPORT
        ════════════════════════════════════════════════════════════════

        WHAT — Algorithm decided:
          Parsed \(parsed.count) digressions from LLM response
          Transcript: \(sentenceCount) sentences sent

        WHAT — Raw data (LLM response):
        \(rawResponse.prefix(2000))
        \(rawResponse.count > 2000 ? "... (truncated, \(rawResponse.count) total chars)" : "")

        WHY — Parsing logic:
        \(parsed.isEmpty ? "  No DIGRESSION| lines found in response" : parsed.enumerated().map { idx, d in
            "  [\(idx + 1)] \(d.type.displayName) s\(d.startSentence)-\(d.endSentence): accepted — valid type, indices in range [0, \(sentenceCount - 1)]"
        }.joined(separator: "\n"))
        ════════════════════════════════════════════════════════════════
        """
    }
}
