//
//  SentenceTaggingService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Tagging mode determines how LLM calls are structured
enum TaggingMode: String, CaseIterable, Identifiable {
    case bulk = "Bulk"              // All sentences in one call (original)
    case perSentence = "Per-Sentence"  // One LLM call per sentence (most granular)
    case batched = "Batched (10)"      // Groups of 10 sentences per call
    case efficient = "Efficient"       // Uses prompt caching for cost savings

    var id: String { rawValue }

    var description: String {
        switch self {
        case .bulk:
            return "All sentences in one LLM call. Fast but may hit token limits."
        case .perSentence:
            return "One LLM call per sentence. Most consistent, runs in parallel."
        case .batched:
            return "10 sentences per LLM call. Balance of speed and consistency."
        case .efficient:
            return "Uses Claude's prompt caching. Same quality, lower cost when run within 5 min."
        }
    }
}

// MARK: - Deterministic Number Detection

/// Detects numbers in text deterministically (no LLM needed)
/// Handles both digit forms ("40", "3.5") and word forms ("forty", "three")
enum NumberDetector {

    /// Check if text contains any number (digits or number words)
    static func hasNumber(in text: String) -> Bool {
        return hasDigits(in: text) || hasNumberWords(in: text)
    }

    /// Check for digit patterns: 40, 3.5, 1,000, $50, 50%, etc.
    private static func hasDigits(in text: String) -> Bool {
        // Pattern matches: standalone digits, decimals, currency, percentages, comma-separated
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Check for number words (case-insensitive word boundary matching)
    private static func hasNumberWords(in text: String) -> Bool {
        let lowercased = text.lowercased()

        // Common number words - check with word boundaries
        let numberWords = [
            // Cardinals 0-19
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
            "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
            "seventeen", "eighteen", "nineteen",
            // Tens
            "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
            // Large numbers
            "hundred", "thousand", "million", "billion", "trillion",
            // Common fractions/amounts
            "half", "quarter", "third", "dozen", "couple"
        ]

        for word in numberWords {
            // Use word boundary check to avoid false positives like "someone" matching "one"
            let pattern = "\\b\(word)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, range: range) != nil {
                    return true
                }
            }
        }

        return false
    }
}

/// Service for running sentence-level tagging on video transcripts
/// Isolated from main ingestion pipeline - used for fidelity testing only
///
/// TWO-STEP ARCHITECTURE:
/// 1. SentenceParser (deterministic) - splits transcript into sentences
/// 2. LLM (tagging only) - tags each pre-split sentence
///
/// DETERMINISTIC FIELDS (computed before LLM):
/// - hasNumber: regex for digits + number words
///
/// TAGGING MODES:
/// - Bulk: All sentences in one call (fast, may hit limits)
/// - Per-Sentence: One call per sentence (most consistent, parallel)
/// - Batched: 10 sentences per call (balanced)
class SentenceTaggingService {

    static let shared = SentenceTaggingService()

    static let currentPromptVersion = "2.1"  // Added per-sentence and batched modes

    // MARK: - Main Tagging Function (Mode-Based)

    /// Tag all sentences in a transcript using the specified mode
    /// Step 1: Use SentenceParser for deterministic splitting
    /// Step 2: Send pre-split sentences to LLM for tagging based on mode
    func tagTranscript(
        transcript: String,
        temperature: Double = 0.1,
        mode: TaggingMode = .bulk,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> [SentenceTelemetry] {
        // STEP 1: Deterministic sentence splitting
        let sentences = SentenceParser.parse(transcript)

        guard !sentences.isEmpty else {
            throw SentenceTaggingError.noTranscript
        }

        let totalSentences = sentences.count

        // STEP 2: LLM tagging based on mode
        switch mode {
        case .bulk:
            return try await tagPreSplitSentences(sentences, temperature: temperature)

        case .perSentence:
            return try await tagPerSentence(
                sentences,
                totalSentences: totalSentences,
                temperature: temperature,
                onProgress: onProgress
            )

        case .batched:
            return try await tagBatched(
                sentences,
                batchSize: 12,
                totalSentences: totalSentences,
                temperature: temperature,
                onProgress: onProgress
            )

        case .efficient:
            return try await tagWithCaching(
                sentences,
                totalSentences: totalSentences,
                temperature: temperature,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Per-Sentence Tagging (Throttled Parallel)

    /// Result type for individual sentence tagging (success or failure)
    private enum SentenceTagResult {
        case success(Int, SentenceTelemetry)
        case failure(Int, String, String, String, String) // index, sentence, rawResponse, cleanedJSON, error
    }

    /// Tag each sentence with its own LLM call, throttled to 5 concurrent
    /// Collects failures instead of throwing immediately
    private func tagPerSentence(
        _ sentences: [String],
        totalSentences: Int,
        temperature: Double,
        onProgress: ((Int, Int) -> Void)?
    ) async throws -> [SentenceTelemetry] {
        let maxConcurrent = 5
        var results: [Int: SentenceTelemetry] = [:]
        var failures: [SentenceTaggingFailure] = []
        var completedCount = 0
        let lock = NSLock()

        // Clear previous failures before starting
        SentenceTaggingDebugStore.shared.clearFailures()

        await withTaskGroup(of: SentenceTagResult.self) { group in
            var iterator = sentences.enumerated().makeIterator()

            // Start initial batch of maxConcurrent tasks
            for _ in 0..<min(maxConcurrent, sentences.count) {
                if let (index, sentence) = iterator.next() {
                    group.addTask {
                        await self.tagSingleSentenceSafe(
                            sentence,
                            index: index,
                            totalSentences: totalSentences,
                            temperature: temperature
                        )
                    }
                }
            }

            // As each completes, add another (sliding window)
            for await result in group {
                lock.lock()
                switch result {
                case .success(let index, let telemetry):
                    results[index] = telemetry
                case .failure(let index, let sentence, let rawResponse, let cleanedJSON, let errorMsg):
                    let failure = SentenceTaggingFailure(
                        sentenceIndex: index,
                        sentenceText: sentence,
                        rawResponse: rawResponse,
                        cleanedJSON: cleanedJSON,
                        errorMessage: errorMsg,
                        timestamp: Date()
                    )
                    failures.append(failure)
                    SentenceTaggingDebugStore.shared.addFailure(failure)
                    print("⚠️ Sentence \(index) failed but continuing: \(errorMsg)")
                }
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, totalSentences)
                }

                // Add next task if available
                if let (nextIndex, nextSentence) = iterator.next() {
                    group.addTask {
                        await self.tagSingleSentenceSafe(
                            nextSentence,
                            index: nextIndex,
                            totalSentences: totalSentences,
                            temperature: temperature
                        )
                    }
                }
            }
        }

        // If ALL sentences failed, throw
        if results.isEmpty && !failures.isEmpty {
            throw SentenceTaggingError.partialFailure(successes: 0, failures: failures)
        }

        // If some failed, log but return what we got
        if !failures.isEmpty {
            print("⚠️ \(failures.count) sentences failed, \(results.count) succeeded")
            print("📋 Use SentenceTaggingDebugStore.shared.allFailuresText to see all failures")
        }

        // Return in order (only successful ones)
        return (0..<sentences.count).compactMap { results[$0] }
    }

    /// Safe wrapper that catches errors and returns a result
    private func tagSingleSentenceSafe(
        _ sentence: String,
        index: Int,
        totalSentences: Int,
        temperature: Double
    ) async -> SentenceTagResult {
        do {
            let telemetry = try await tagSingleSentence(
                sentence,
                index: index,
                totalSentences: totalSentences,
                temperature: temperature
            )
            return .success(index, telemetry)
        } catch let error as SentenceTaggingErrorWithContext {
            // Error includes debug context
            return .failure(
                index,
                sentence,
                error.rawResponse,
                error.cleanedJSON,
                error.underlyingMessage
            )
        } catch {
            // Generic error without context
            return .failure(
                index,
                sentence,
                "No response captured",
                "No JSON captured",
                error.localizedDescription
            )
        }
    }

    /// Tag a single sentence with one LLM call
    private func tagSingleSentence(
        _ sentence: String,
        index: Int,
        totalSentences: Int,
        temperature: Double
    ) async throws -> SentenceTelemetry {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let systemPrompt = """
        You are tagging a single sentence from a YouTube video transcript.
        Output ONLY a valid JSON object with the required fields.
        Be consistent: identical sentence patterns should get identical tags.
        When genuinely uncertain, default to false for booleans and "neutral" for stance.
        No commentary. No explanation. Just the JSON object.
        """

        let positionPercentile = Double(index) / Double(totalSentences)

        let userPrompt = """
        Tag this sentence (index \(index) of \(totalSentences), position \(String(format: "%.2f", positionPercentile))):

        "\(sentence)"

        Output a JSON object with these fields:

        IDENTITY
        - sentenceIndex: \(index)
        - text: "\(sentence)"
        - positionPercentile: \(String(format: "%.4f", positionPercentile))

        SURFACE STRUCTURE
        - wordCount: number of words
        - hasNumber: false (placeholder - computed separately)
        - endsWithQuestion: true if ends with ?
        - endsWithExclamation: true if ends with !

        LEXICAL SIGNALS
        - hasContrastMarker: true if contains "but", "however", "yet", "actually", "though", "instead"
        - hasTemporalMarker: true if contains years, dates, "then", "later", "earlier", "now", "back then"
        - hasFirstPerson: true if contains "I", "me", "my", "we", "our"
        - hasSecondPerson: true if contains "you", "your"

        CONTENT MARKERS
        - hasStatistic: true if number WITH meaningful context (percentage, quantity, data claim)
        - hasQuote: true if contains attributed speech or quotation marks
        - hasNamedEntity: true ONLY if contains a proper noun referring to a specific person, company, or study (e.g., "Elon Musk", "Google", "Harvard study") — NOT generic terms like "the company" or "researchers"

        RHETORICAL MARKERS
        - hasRevealLanguage: true if exposes something hidden ("the truth is", "here's the thing", "turns out")
        - hasPromiseLanguage: true if promises future content ("I'll show you", "let me explain")
        - hasChallengeLanguage: true if questions common belief ("everyone thinks", "you've been told")

        STANCE & PERSPECTIVE
        - stance: "asserting" | "questioning" | "challenging" | "neutral"
        - perspective: "first" | "second" | "third"

        STRUCTURAL
        - isTransition: true if primarily moves between topics
        - isSponsorContent: true if brand promotion or ad read
        - isCallToAction: true if asking viewer to subscribe, like, comment

        Output ONLY the JSON object. No markdown. No explanation.
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 500]
        )

        // Debug: print raw response for troubleshooting
        print("📝 Sentence \(index) raw response (first 300 chars):")
        print(String(response.prefix(300)))

        return try parseSingleResponse(response, index: index, originalSentence: sentence, totalSentences: totalSentences)
    }

    // MARK: - Efficient Cached Tagging

    /// Tag sentences using Claude's prompt caching for cost efficiency
    /// The large instruction prompt is cached, only the sentence varies
    /// This can reduce costs significantly when processing many sentences within 5 minutes
    func tagWithCaching(
        _ sentences: [String],
        totalSentences: Int,
        temperature: Double,
        onProgress: ((Int, Int) -> Void)?
    ) async throws -> [SentenceTelemetry] {
        let maxConcurrent = 10
        var results: [Int: SentenceTelemetry] = [:]
        var failures: [SentenceTaggingFailure] = []
        var completedCount = 0
        let lock = NSLock()

        // Clear previous failures before starting
        SentenceTaggingDebugStore.shared.clearFailures()

        // The cacheable prompt - this stays the same for every sentence
        let cacheablePrompt = buildCacheablePrompt(totalSentences: totalSentences)

        await withTaskGroup(of: SentenceTagResult.self) { group in
            var iterator = sentences.enumerated().makeIterator()

            // Start initial batch
            for _ in 0..<min(maxConcurrent, sentences.count) {
                if let (index, sentence) = iterator.next() {
                    group.addTask {
                        await self.tagSingleSentenceWithCaching(
                            sentence,
                            index: index,
                            totalSentences: totalSentences,
                            temperature: temperature,
                            cacheablePrompt: cacheablePrompt
                        )
                    }
                }
            }

            // Process results with sliding window
            for await result in group {
                lock.lock()
                switch result {
                case .success(let index, let telemetry):
                    results[index] = telemetry
                case .failure(let index, let sentence, let rawResponse, let cleanedJSON, let errorMsg):
                    let failure = SentenceTaggingFailure(
                        sentenceIndex: index,
                        sentenceText: sentence,
                        rawResponse: rawResponse,
                        cleanedJSON: cleanedJSON,
                        errorMessage: errorMsg,
                        timestamp: Date()
                    )
                    failures.append(failure)
                    SentenceTaggingDebugStore.shared.addFailure(failure)
                    print("⚠️ Cached sentence \(index) failed: \(errorMsg)")
                }
                completedCount += 1
                let count = completedCount
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, totalSentences)
                }

                // Add next task
                if let (nextIndex, nextSentence) = iterator.next() {
                    group.addTask {
                        await self.tagSingleSentenceWithCaching(
                            nextSentence,
                            index: nextIndex,
                            totalSentences: totalSentences,
                            temperature: temperature,
                            cacheablePrompt: cacheablePrompt
                        )
                    }
                }
            }
        }

        if results.isEmpty && !failures.isEmpty {
            throw SentenceTaggingError.partialFailure(successes: 0, failures: failures)
        }

        if !failures.isEmpty {
            print("⚠️ Cached tagging: \(failures.count) failed, \(results.count) succeeded")
        }

        return (0..<sentences.count).compactMap { results[$0] }
    }

    /// Build the large cacheable prompt with all instructions
    /// This is the part that gets cached by Claude
    /// NOTE: Must be at least 1024 tokens for caching to be effective
    private func buildCacheablePrompt(totalSentences: Int) -> String {
        """
        You are an expert linguistic analyst tagging sentences from YouTube video transcripts.
        Your task is to analyze each sentence and output structured telemetry data.

        CRITICAL RULES:
        1. Output ONLY a valid JSON object. No markdown code blocks. No explanation. No commentary.
        2. Be deterministic: identical sentence patterns must receive identical tags across runs.
        3. When genuinely uncertain, default to false for booleans and "neutral" for stance.
        4. Read each sentence carefully and tag based ONLY on what is explicitly present.

        For the sentence provided, output a JSON object with these exact fields:

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 1: IDENTITY FIELDS
        ═══════════════════════════════════════════════════════════════════════════════

        sentenceIndex: (integer) The index number provided with the sentence
        text: (string) The exact sentence text, copied verbatim
        positionPercentile: (float) sentenceIndex / \(totalSentences), ranging from 0.0 to 1.0

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 2: SURFACE STRUCTURE (Observable Features)
        ═══════════════════════════════════════════════════════════════════════════════

        wordCount: (integer) Count of words in the sentence, separated by whitespace
        hasNumber: (boolean) Always set to false - this is computed separately via regex
        endsWithQuestion: (boolean) true if the sentence ends with a question mark (?)
        endsWithExclamation: (boolean) true if the sentence ends with an exclamation mark (!)

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 3: LEXICAL SIGNALS (Keyword Detection)
        ═══════════════════════════════════════════════════════════════════════════════

        hasContrastMarker: (boolean) true if contains contrast words
          LOOK FOR: "but", "however", "yet", "actually", "though", "instead", "although", "nevertheless"
          EXAMPLES:
            "I thought it would work, but it didn't" → true
            "However, the results were surprising" → true
            "The food was good" → false

        hasTemporalMarker: (boolean) true if contains time references
          LOOK FOR: years (2024, 1990s), dates, "then", "later", "earlier", "now", "back then", "recently", "before", "after", "when"
          EXAMPLES:
            "Back in 2020, everything changed" → true
            "Then I realized the mistake" → true
            "The car is red" → false

        hasFirstPerson: (boolean) true if contains first-person pronouns
          LOOK FOR: "I", "me", "my", "myself", "we", "us", "our", "ourselves"
          EXAMPLES:
            "I think this is important" → true
            "We built this from scratch" → true
            "You should try this" → false

        hasSecondPerson: (boolean) true if contains second-person pronouns
          LOOK FOR: "you", "your", "yourself", "yourselves"
          EXAMPLES:
            "You need to understand this" → true
            "This is your opportunity" → true
            "They went to the store" → false

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 4: CONTENT MARKERS (Semantic Analysis)
        ═══════════════════════════════════════════════════════════════════════════════

        hasStatistic: (boolean) true if contains a number WITH meaningful context
          REQUIRES: A number AND context showing it's data/measurement (percentage, quantity, comparison)
          NOT: random digits, addresses, or numbers without statistical meaning
          EXAMPLES:
            "Studies show 73% of users prefer this method" → true
            "The company grew by 400% in two years" → true
            "I went to 42nd street" → false (address, not statistic)
            "Let me show you 3 tips" → false (count, not statistic)

        hasQuote: (boolean) true if contains quoted speech or quotation marks
          LOOK FOR: quotation marks (""), attributed speech, direct quotes
          EXAMPLES:
            'He said "this changes everything"' → true
            "As Einstein famously stated, 'imagination is more important than knowledge'" → true
            "The meeting was productive" → false

        hasNamedEntity: (boolean) true ONLY if contains a proper noun
          REQUIRES: Specific person name, company name, organization, or named study
          NOT: Generic terms like "the company", "researchers", "scientists", "experts"
          EXAMPLES:
            "Elon Musk announced the new product" → true
            "A Harvard study confirmed this" → true
            "Google released an update" → true
            "The company reported earnings" → false (generic)
            "Researchers found that..." → false (generic)

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 5: RHETORICAL MARKERS (Persuasive Patterns)
        ═══════════════════════════════════════════════════════════════════════════════

        hasRevealLanguage: (boolean) true if exposing hidden information
          LOOK FOR: "the truth is", "what they don't tell you", "here's the thing", "the real reason",
                    "turns out", "actually", "the secret is", "what most people don't know"
          EXAMPLES:
            "Here's the thing nobody talks about" → true
            "The truth is, it's much simpler than they make it seem" → true
            "The product has three features" → false

        hasPromiseLanguage: (boolean) true if promising future content
          LOOK FOR: "I'll show you", "we'll see", "let me explain", "here's why", "stick around",
                    "I'm going to reveal", "by the end of this video", "coming up"
          EXAMPLES:
            "I'll show you exactly how this works" → true
            "Stick around because this gets interesting" → true
            "The results were conclusive" → false

        hasChallengeLanguage: (boolean) true if questioning common beliefs
          LOOK FOR: "everyone thinks", "you've been told", "the official story", "most people believe",
                    "conventional wisdom", "what you've heard", "contrary to popular belief"
          EXAMPLES:
            "Everyone thinks this is impossible, but it's not" → true
            "You've been told that fat is bad for you" → true
            "The data supports this conclusion" → false

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 6: STANCE CLASSIFICATION
        ═══════════════════════════════════════════════════════════════════════════════

        stance: (string) Choose exactly ONE of these four values:

        "asserting" — The speaker is stating something as fact with confidence
          EXAMPLES: "This is the best approach", "The data clearly shows", "This works because"

        "questioning" — The speaker is exploring, uncertain, or expressing curiosity
          EXAMPLES: "Could this be the answer?", "I wonder if", "What if we tried"

        "challenging" — The speaker is pushing back, being critical, or adversarial
          EXAMPLES: "That's completely wrong", "This is a myth", "Don't believe the hype"

        "neutral" — Transitional content, factual without clear stance, or descriptive
          EXAMPLES: "Moving on to the next topic", "The product comes in three colors", "Let's begin"

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 7: PERSPECTIVE CLASSIFICATION
        ═══════════════════════════════════════════════════════════════════════════════

        perspective: (string) Choose exactly ONE of these three values:

        "first" — Narrator voice using I/we pronouns
          EXAMPLES: "I built this system", "We discovered something interesting"

        "second" — Addressing the viewer directly using you pronouns
          EXAMPLES: "You need to see this", "Your results will vary"

        "third" — Describing others using he/she/they/it pronouns, or no pronouns
          EXAMPLES: "The company announced", "They released the product", "Scientists discovered"

        ═══════════════════════════════════════════════════════════════════════════════
        SECTION 8: STRUCTURAL MARKERS
        ═══════════════════════════════════════════════════════════════════════════════

        isTransition: (boolean) true if sentence primarily moves between topics
          LOOK FOR: "Now let's", "Moving on", "So anyway", "Next up", "Speaking of which"
          EXAMPLES:
            "Now let's talk about the pricing" → true
            "Anyway, moving on to the next point" → true
            "The price is $29.99" → false

        isSponsorContent: (boolean) true if this is brand promotion or ad read
          LOOK FOR: sponsor mentions, promotional language, affiliate disclosures
          EXAMPLES:
            "This video is sponsored by NordVPN" → true
            "Use code SAVE20 for a discount" → true
            "I personally recommend this product" → false (unless clearly sponsored)

        isCallToAction: (boolean) true if asking viewer to engage
          LOOK FOR: "subscribe", "like", "comment", "click", "share", "hit the bell"
          EXAMPLES:
            "Don't forget to subscribe and hit the bell" → true
            "Let me know in the comments what you think" → true
            "I appreciate your support" → false

        ═══════════════════════════════════════════════════════════════════════════════
        OUTPUT FORMAT
        ═══════════════════════════════════════════════════════════════════════════════

        Output a single JSON object containing ALL fields listed above.
        Do NOT wrap in markdown code blocks.
        Do NOT include any explanation or commentary.
        Just the raw JSON object.

        Example output structure:
        {
          "sentenceIndex": 0,
          "text": "...",
          "positionPercentile": 0.0,
          "wordCount": 5,
          "hasNumber": false,
          "endsWithQuestion": false,
          "endsWithExclamation": false,
          "hasContrastMarker": false,
          "hasTemporalMarker": false,
          "hasFirstPerson": true,
          "hasSecondPerson": false,
          "hasStatistic": false,
          "hasQuote": false,
          "hasNamedEntity": false,
          "hasRevealLanguage": false,
          "hasPromiseLanguage": false,
          "hasChallengeLanguage": false,
          "stance": "asserting",
          "perspective": "first",
          "isTransition": false,
          "isSponsorContent": false,
          "isCallToAction": false
        }
        """
    }

    /// Tag a single sentence using cached prompt
    private func tagSingleSentenceWithCaching(
        _ sentence: String,
        index: Int,
        totalSentences: Int,
        temperature: Double,
        cacheablePrompt: String
    ) async -> SentenceTagResult {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
        let positionPercentile = Double(index) / Double(totalSentences)

        // The variable part - just the sentence and its index
        let variablePrompt = """
        Sentence index: \(index)
        Position: \(String(format: "%.4f", positionPercentile))

        Sentence to tag:
        "\(sentence)"
        """

        guard let response = await adapter.generate_cached_response(
            prompt: variablePrompt,
            cacheablePromptBackgroundInfo: cacheablePrompt,
            params: ["temperature": temperature, "max_tokens": 600]
        ) else {
            return .failure(index, sentence, "No response", "", "generate_cached_response returned nil")
        }

        // Parse the response
        do {
            let telemetry = try parseSingleResponse(
                response.content,
                index: index,
                originalSentence: sentence,
                totalSentences: totalSentences
            )
            return .success(index, telemetry)
        } catch let error as SentenceTaggingErrorWithContext {
            return .failure(index, sentence, error.rawResponse, error.cleanedJSON, error.underlyingMessage)
        } catch {
            return .failure(index, sentence, response.content, "", error.localizedDescription)
        }
    }

    // MARK: - Batched Tagging (Throttled Parallel)

    /// Result type for batch tagging (success or failure)
    private enum BatchTagResult {
        case success(Int, [SentenceTelemetry])
        case failure(Int, [String], String, String, String) // batchIndex, sentences, rawResponse, cleanedJSON, error
    }

    /// Tag sentences in batches (10 at a time), with 10 concurrent batch calls
    /// This means up to 100 sentences can be processed simultaneously
    /// Collects failures instead of throwing immediately
    private func tagBatched(
        _ sentences: [String],
        batchSize: Int,
        totalSentences: Int,
        temperature: Double,
        onProgress: ((Int, Int) -> Void)?
    ) async throws -> [SentenceTelemetry] {
        let maxConcurrent = 6  // 6 batches of 12 sentences = 72 sentences at once per video
        let batches = sentences.chunked(into: batchSize)
        var results: [Int: [SentenceTelemetry]] = [:]
        var failures: [SentenceTaggingFailure] = []
        var completedSentences = 0
        let lock = NSLock()

        // Clear previous failures before starting
        SentenceTaggingDebugStore.shared.clearFailures()

        await withTaskGroup(of: BatchTagResult.self) { group in
            var iterator = batches.enumerated().makeIterator()

            // Start initial batch of maxConcurrent tasks
            for _ in 0..<min(maxConcurrent, batches.count) {
                if let (batchIndex, batch) = iterator.next() {
                    let startIndex = batchIndex * batchSize
                    group.addTask {
                        await self.tagBatchSafe(
                            batch,
                            batchIndex: batchIndex,
                            startIndex: startIndex,
                            totalSentences: totalSentences,
                            temperature: temperature
                        )
                    }
                }
            }

            // As each completes, add another (sliding window)
            for await result in group {
                lock.lock()
                switch result {
                case .success(let batchIndex, let batchResults):
                    results[batchIndex] = batchResults
                    completedSentences += batchResults.count
                case .failure(let batchIndex, let batchSentences, let rawResponse, let cleanedJSON, let errorMsg):
                    // Create a failure entry for the whole batch
                    let failure = SentenceTaggingFailure(
                        sentenceIndex: batchIndex * batchSize,
                        sentenceText: "BATCH \(batchIndex) (\(batchSentences.count) sentences): " + batchSentences.prefix(3).joined(separator: " | "),
                        rawResponse: rawResponse,
                        cleanedJSON: cleanedJSON,
                        errorMessage: errorMsg,
                        timestamp: Date()
                    )
                    failures.append(failure)
                    SentenceTaggingDebugStore.shared.addFailure(failure)
                    completedSentences += batchSentences.count // Count as "processed" even if failed
                    print("⚠️ Batch \(batchIndex) failed but continuing: \(errorMsg)")
                }
                let count = completedSentences
                lock.unlock()

                await MainActor.run {
                    onProgress?(count, totalSentences)
                }

                // Add next batch if available
                if let (nextBatchIndex, nextBatch) = iterator.next() {
                    let nextStartIndex = nextBatchIndex * batchSize
                    group.addTask {
                        await self.tagBatchSafe(
                            nextBatch,
                            batchIndex: nextBatchIndex,
                            startIndex: nextStartIndex,
                            totalSentences: totalSentences,
                            temperature: temperature
                        )
                    }
                }
            }
        }

        // If ALL batches failed, throw
        if results.isEmpty && !failures.isEmpty {
            throw SentenceTaggingError.partialFailure(successes: 0, failures: failures)
        }

        // If some failed, log but return what we got
        if !failures.isEmpty {
            let successCount = results.values.flatMap { $0 }.count
            print("⚠️ \(failures.count) batches failed, \(successCount) sentences succeeded")
            print("📋 Use SentenceTaggingDebugStore.shared.allFailuresText to see all failures")
        }

        // Return in order (only successful batches)
        return (0..<batches.count).flatMap { results[$0] ?? [] }
    }

    /// Safe wrapper that catches errors and returns a result
    private func tagBatchSafe(
        _ sentences: [String],
        batchIndex: Int,
        startIndex: Int,
        totalSentences: Int,
        temperature: Double
    ) async -> BatchTagResult {
        do {
            let telemetry = try await tagBatch(
                sentences,
                startIndex: startIndex,
                totalSentences: totalSentences,
                temperature: temperature
            )
            return .success(batchIndex, telemetry)
        } catch let error as SentenceTaggingErrorWithContext {
            return .failure(
                batchIndex,
                sentences,
                error.rawResponse,
                error.cleanedJSON,
                error.underlyingMessage
            )
        } catch {
            return .failure(
                batchIndex,
                sentences,
                "No response captured",
                "No JSON captured",
                error.localizedDescription
            )
        }
    }

    /// Tag a batch of sentences with one LLM call
    private func tagBatch(
        _ sentences: [String],
        startIndex: Int,
        totalSentences: Int,
        temperature: Double
    ) async throws -> [SentenceTelemetry] {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let numberedSentences = sentences.enumerated().map { offset, text in
            let globalIndex = startIndex + offset
            return "[\(globalIndex)] \(text)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are tagging pre-split sentences from a YouTube video transcript.
        The sentences have ALREADY been split. Your ONLY job is to TAG each one.
        Be consistent: identical sentence patterns should get identical tags.
        When genuinely uncertain, default to false for booleans and "neutral" for stance.
        Output ONLY valid JSON. No commentary.
        """

        let userPrompt = """
        Tag these \(sentences.count) sentences (indices \(startIndex) to \(startIndex + sentences.count - 1) of \(totalSentences) total):

        \(numberedSentences)

        For EACH sentence, output a JSON object with:

        IDENTITY
        - sentenceIndex: the number in brackets
        - text: exact sentence text
        - positionPercentile: sentenceIndex / \(totalSentences)

        SURFACE: wordCount, hasNumber (set to false - computed separately), endsWithQuestion, endsWithExclamation
        LEXICAL: hasContrastMarker, hasTemporalMarker, hasFirstPerson, hasSecondPerson
        CONTENT: hasStatistic, hasQuote, hasNamedEntity (true ONLY for proper nouns: specific person, company, or study name)
        RHETORICAL: hasRevealLanguage, hasPromiseLanguage, hasChallengeLanguage
        stance: "asserting" | "questioning" | "challenging" | "neutral"
        perspective: "first" | "second" | "third"
        STRUCTURAL: isTransition, isSponsorContent, isCallToAction

        Output a JSON array with exactly \(sentences.count) objects. No commentary.
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 4000]
        )

        return try parseResponse(response)
    }

    // MARK: - Legacy Bulk Tagging

    /// Tag pre-split sentences (LLM does tagging only, not splitting)
    private func tagPreSplitSentences(
        _ sentences: [String],
        temperature: Double
    ) async throws -> [SentenceTelemetry] {
        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        // Build numbered sentence list for the prompt
        let numberedSentences = sentences.enumerated().map { idx, text in
            "[\(idx)] \(text)"
        }.joined(separator: "\n")

        let totalSentences = sentences.count

        let systemPrompt = """
        You are tagging pre-split sentences from a YouTube video transcript.

        The sentences have ALREADY been split for you. Your ONLY job is to TAG each one.
        Do NOT re-split, merge, or modify the sentence boundaries.

        For each sentence, answer observable and interpretive questions about what is present IN THAT SENTENCE.

        Be consistent: identical sentence patterns should get identical tags across runs.
        When genuinely uncertain, default to false for booleans and "neutral" for stance.

        Output ONLY valid JSON. No commentary.
        """

        let userPrompt = """
        Below are \(totalSentences) pre-split sentences from a video transcript.
        Each is prefixed with its index: [0], [1], [2], etc.

        For EACH sentence, output a JSON object with these fields:

        ---

        IDENTITY
        - sentenceIndex: the number in brackets (0, 1, 2, ...)
        - text: the exact sentence text (copy it exactly as given)
        - positionPercentile: sentenceIndex / \(totalSentences) (0.0 to 1.0)

        SURFACE STRUCTURE (count/check directly)
        - wordCount: number of words
        - hasNumber: false (placeholder - computed separately via regex)
        - endsWithQuestion: true if ends with ?
        - endsWithExclamation: true if ends with !

        LEXICAL SIGNALS (keyword matching)
        - hasContrastMarker: true if contains "but", "however", "yet", "actually", "though", "instead"
        - hasTemporalMarker: true if contains years, dates, "then", "later", "earlier", "now", "back then"
        - hasFirstPerson: true if contains "I", "me", "my", "we", "our"
        - hasSecondPerson: true if contains "you", "your"

        CONTENT MARKERS (interpret what's present)
        - hasStatistic: true if contains a number WITH meaningful context (percentage, quantity, data claim) — not just any digit
        - hasQuote: true if contains attributed speech or quotation marks
        - hasNamedEntity: true ONLY if contains a proper noun referring to a specific person, company, or study (e.g., "Elon Musk", "Google", "Harvard study") — NOT generic terms like "the company" or "researchers"

        RHETORICAL MARKERS (interpret the move being made)
        - hasRevealLanguage: true if contains language exposing something hidden
          Look for: "the truth is", "what they don't tell you", "here's the thing", "the real reason", "turns out", "actually"
        - hasPromiseLanguage: true if contains language promising future content
          Look for: "I'll show you", "we'll see", "let me explain", "here's why", "stick around"
        - hasChallengeLanguage: true if contains language questioning common belief
          Look for: "everyone thinks", "you've been told", "the official story", "most people believe", "conventional wisdom"

        STANCE (interpret the posture)
        - stance: Choose ONE of:
          - "asserting" — stating something as fact with confidence
          - "questioning" — exploring, uncertain, curious
          - "challenging" — pushing back, critical, adversarial
          - "neutral" — transitional, factual without clear stance

        PERSPECTIVE
        - perspective: Choose ONE of:
          - "first" — narrator voice (I, we)
          - "second" — addressing viewer (you)
          - "third" — describing others (he, she, they, it)

        STRUCTURAL MARKERS
        - isTransition: true if sentence primarily moves between topics ("Now let's", "Moving on", "So anyway")
        - isSponsorContent: true if brand promotion or ad read
        - isCallToAction: true if asking viewer to subscribe, like, comment, click

        ---

        Output a JSON array with exactly \(totalSentences) sentence telemetry objects.
        The array index must match the sentenceIndex.
        No commentary. No explanations. Just the JSON array.

        SENTENCES:
        \(numberedSentences)
        """

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: ["temperature": temperature, "max_tokens": 32000]
        )

        return try parseResponse(response)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: String) throws -> [SentenceTelemetry] {
        let jsonString = extractAndCleanJSON(from: response)

        guard !jsonString.isEmpty else {
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Could not extract JSON from response",
                rawResponse: response,
                cleanedJSON: "(empty)"
            )
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Could not convert response to data",
                rawResponse: response,
                cleanedJSON: jsonString
            )
        }

        do {
            let sentences = try JSONDecoder().decode([SentenceTelemetry].self, from: data)
            // Apply deterministic hasNumber override
            return sentences.map { applyDeterministicFields($0) }
        } catch {
            // Log the problematic JSON for debugging
            print("❌ JSON Parse Error. First 500 chars of cleaned JSON:")
            print(String(jsonString.prefix(500)))
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Failed to parse sentences: \(error.localizedDescription)",
                rawResponse: response,
                cleanedJSON: jsonString
            )
        }
    }

    /// Apply deterministic field overrides (hasNumber computed via regex, not LLM)
    private func applyDeterministicFields(_ sentence: SentenceTelemetry) -> SentenceTelemetry {
        let deterministicHasNumber = NumberDetector.hasNumber(in: sentence.text)

        return SentenceTelemetry(
            sentenceIndex: sentence.sentenceIndex,
            text: sentence.text,
            positionPercentile: sentence.positionPercentile,
            wordCount: sentence.wordCount,
            hasNumber: deterministicHasNumber, // OVERRIDE with deterministic value
            endsWithQuestion: sentence.endsWithQuestion,
            endsWithExclamation: sentence.endsWithExclamation,
            hasContrastMarker: sentence.hasContrastMarker,
            hasTemporalMarker: sentence.hasTemporalMarker,
            hasFirstPerson: sentence.hasFirstPerson,
            hasSecondPerson: sentence.hasSecondPerson,
            hasStatistic: sentence.hasStatistic,
            hasQuote: sentence.hasQuote,
            hasNamedEntity: sentence.hasNamedEntity,
            hasRevealLanguage: sentence.hasRevealLanguage,
            hasPromiseLanguage: sentence.hasPromiseLanguage,
            hasChallengeLanguage: sentence.hasChallengeLanguage,
            stance: sentence.stance,
            perspective: sentence.perspective,
            isTransition: sentence.isTransition,
            isSponsorContent: sentence.isSponsorContent,
            isCallToAction: sentence.isCallToAction
        )
    }

    private func parseSingleResponse(_ response: String, index: Int, originalSentence: String, totalSentences: Int) throws -> SentenceTelemetry {
        let jsonString = extractAndCleanJSON(from: response)

        print("📋 Sentence \(index) cleaned JSON (first 400 chars):")
        print(String(jsonString.prefix(400)))

        guard !jsonString.isEmpty else {
            print("❌ Empty JSON for sentence \(index)")
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Could not extract JSON for sentence \(index)",
                rawResponse: response,
                cleanedJSON: "(empty)"
            )
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Could not convert response to data for sentence \(index)",
                rawResponse: response,
                cleanedJSON: jsonString
            )
        }

        do {
            var sentence = try JSONDecoder().decode(SentenceTelemetry.self, from: data)

            // Always apply deterministic hasNumber (computed via regex, not LLM)
            let deterministicHasNumber = NumberDetector.hasNumber(in: sentence.text.isEmpty ? originalSentence : sentence.text)

            // Correct any missing/default values with the known values AND apply deterministic fields
            let correctedPercentile = Double(index) / Double(totalSentences)
            sentence = SentenceTelemetry(
                sentenceIndex: sentence.sentenceIndex == -1 ? index : sentence.sentenceIndex,
                text: sentence.text.isEmpty ? originalSentence : sentence.text,
                positionPercentile: sentence.positionPercentile == 0.0 ? correctedPercentile : sentence.positionPercentile,
                wordCount: sentence.wordCount == 0 ? originalSentence.split(separator: " ").count : sentence.wordCount,
                hasNumber: deterministicHasNumber, // OVERRIDE with deterministic value
                endsWithQuestion: sentence.endsWithQuestion,
                endsWithExclamation: sentence.endsWithExclamation,
                hasContrastMarker: sentence.hasContrastMarker,
                hasTemporalMarker: sentence.hasTemporalMarker,
                hasFirstPerson: sentence.hasFirstPerson,
                hasSecondPerson: sentence.hasSecondPerson,
                hasStatistic: sentence.hasStatistic,
                hasQuote: sentence.hasQuote,
                hasNamedEntity: sentence.hasNamedEntity,
                hasRevealLanguage: sentence.hasRevealLanguage,
                hasPromiseLanguage: sentence.hasPromiseLanguage,
                hasChallengeLanguage: sentence.hasChallengeLanguage,
                stance: sentence.stance,
                perspective: sentence.perspective,
                isTransition: sentence.isTransition,
                isSponsorContent: sentence.isSponsorContent,
                isCallToAction: sentence.isCallToAction
            )

            return sentence
        } catch let decodingError as DecodingError {
            var errorDetail = "Failed to parse sentence \(index): "
            switch decodingError {
            case .keyNotFound(let key, _):
                errorDetail += "Missing key: \(key.stringValue)"
            case .typeMismatch(let type, let context):
                errorDetail += "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .valueNotFound(let type, let context):
                errorDetail += "Value not found: \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .dataCorrupted(let context):
                errorDetail += "Data corrupted: \(context.debugDescription)"
            @unknown default:
                errorDetail += decodingError.localizedDescription
            }
            print("❌ \(errorDetail)")
            print("   Full JSON:")
            print(jsonString)
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: errorDetail,
                rawResponse: response,
                cleanedJSON: jsonString
            )
        } catch {
            print("❌ Unexpected error for sentence \(index): \(error)")
            throw SentenceTaggingErrorWithContext(
                underlyingMessage: "Failed to parse sentence \(index): \(error.localizedDescription)",
                rawResponse: response,
                cleanedJSON: jsonString
            )
        }
    }

    /// Main extraction function - handles all response formats
    private func extractAndCleanJSON(from response: String) -> String {
        var text = response

        // STEP 1: If this looks like a full API response, extract the text content
        if text.contains("\"content\"") && text.contains("\"type\":\"text\"") {
            if let extracted = extractTextFromAPIResponse(text) {
                text = extracted
            }
        }

        // STEP 2: Find the JSON array or object within the text
        // Look for [ ... ] or { ... } patterns
        text = extractJSONFromText(text)

        // STEP 3: Fix boolean fields that Claude returns as numbers
        text = fixBooleanFields(text)

        // STEP 4: Remove duplicate keys (Claude sometimes outputs duplicate keys)
        text = removeDuplicateKeys(text)

        return text
    }

    /// Extract text content from full Claude API response JSON
    private func extractTextFromAPIResponse(_ response: String) -> String? {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            return nil
        }
        return text
    }

    /// Extract JSON array or object from text that may contain markdown or other content
    private func extractJSONFromText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks - handle various formats
        // ```json ... ``` or ``` ... ```
        if let jsonBlockRange = cleaned.range(of: "```json") {
            cleaned = String(cleaned[jsonBlockRange.upperBound...])
        } else if let codeBlockRange = cleaned.range(of: "```") {
            cleaned = String(cleaned[codeBlockRange.upperBound...])
        }

        // Remove trailing ```
        if let endBlockRange = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<endBlockRange.lowerBound])
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // STRATEGY: Find BOTH [ and { positions, use whichever comes first
        // This handles:
        // - Arrays with whitespace: "[\n  {\n" (common in formatted JSON)
        // - Single objects: "{\n"
        // - Inline arrays: "[{"

        let arrayStart = cleaned.firstIndex(of: "[")
        let objectStart = cleaned.firstIndex(of: "{")

        // Determine which structure comes first
        let useArray: Bool
        if let arr = arrayStart, let obj = objectStart {
            useArray = arr < obj
        } else if arrayStart != nil {
            useArray = true
        } else {
            useArray = false
        }

        if useArray, let start = arrayStart {
            // Extract the array - verify it's a JSON array (contains objects with keys)
            if let end = findMatchingBracket(in: cleaned, from: start, open: "[", close: "]") {
                let candidate = String(cleaned[start...end])
                // Verify it looks like JSON array of objects (has ":" for key-value pairs)
                if candidate.contains(":") && candidate.contains("\"") {
                    return candidate
                }
            }
        }

        // Fall back to single object extraction
        if let start = objectStart {
            if let end = findMatchingBracket(in: cleaned, from: start, open: "{", close: "}") {
                return String(cleaned[start...end])
            }
        }

        return cleaned
    }

    /// Find matching closing bracket accounting for nesting
    private func findMatchingBracket(in text: String, from start: String.Index, open: Character, close: Character) -> String.Index? {
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
                if char == open {
                    depth += 1
                } else if char == close {
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

    /// Fix boolean fields that Claude sometimes returns as numbers (1/0/400 instead of true/false)
    private func fixBooleanFields(_ jsonString: String) -> String {
        var fixed = jsonString

        let booleanFields = [
            "hasNumber", "endsWithQuestion", "endsWithExclamation",
            "hasContrastMarker", "hasTemporalMarker", "hasFirstPerson", "hasSecondPerson",
            "hasStatistic", "hasQuote", "hasNamedEntity",
            "hasRevealLanguage", "hasPromiseLanguage", "hasChallengeLanguage",
            "isTransition", "isSponsorContent", "isCallToAction"
        ]

        for field in booleanFields {
            // Pattern: "fieldName": <number> (handles any integer)
            let pattern = "\"\(field)\"\\s*:\\s*(\\d+)"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(fixed.startIndex..., in: fixed)
                let matches = regex.matches(in: fixed, range: range)

                for match in matches.reversed() {
                    if let numberRange = Range(match.range(at: 1), in: fixed),
                       let fullRange = Range(match.range, in: fixed) {
                        let numberStr = String(fixed[numberRange])
                        let boolValue = (Int(numberStr) ?? 0) != 0 ? "true" : "false"
                        fixed.replaceSubrange(fullRange, with: "\"\(field)\": \(boolValue)")
                    }
                }
            }
        }

        return fixed
    }

    /// Remove duplicate keys from JSON (Claude sometimes outputs the same key twice)
    private func removeDuplicateKeys(_ jsonString: String) -> String {
        // This is a simple approach - for each object, track seen keys and remove duplicates
        // We'll use a line-by-line approach since JSON is typically formatted with newlines

        var lines = jsonString.components(separatedBy: "\n")
        var seenKeysInCurrentObject: Set<String> = []
        var objectDepth = 0
        var indicesToRemove: [Int] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track object depth
            objectDepth += trimmed.filter { $0 == "{" }.count
            objectDepth -= trimmed.filter { $0 == "}" }.count

            // Reset seen keys when entering a new object
            if trimmed.contains("{") {
                seenKeysInCurrentObject = []
            }

            // Extract key if this line has one
            if let colonRange = trimmed.range(of: ":"),
               trimmed.first == "\"" {
                let keyPart = String(trimmed[..<colonRange.lowerBound])
                let key = keyPart.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

                if seenKeysInCurrentObject.contains(key) {
                    // Duplicate key - mark for removal
                    indicesToRemove.append(index)
                } else {
                    seenKeysInCurrentObject.insert(key)
                }
            }
        }

        // Remove duplicate lines in reverse order
        for index in indicesToRemove.reversed() {
            lines.remove(at: index)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Array Chunking Helper

//extension Array {
//    func chunked(into size: Int) -> [[Element]] {
//        guard size > 0 else { return [self] }
//        return stride(from: 0, to: count, by: size).map {
//            Array(self[$0..<Swift.min($0 + size, count)])
//        }
//    }
//}

// MARK: - Comparison Logic

extension SentenceTaggingService {

    /// Compare two test runs and calculate stability metrics
    func compareRuns(_ run1: SentenceFidelityTest, _ run2: SentenceFidelityTest) -> FidelityComparisonResult {
        var fieldAgreements: [SentenceTelemetryField: Int] = [:]
        var fieldTotals: [SentenceTelemetryField: Int] = [:]
        var disagreements: [SentenceDisagreement] = []

        // Initialize counters
        for field in SentenceTelemetryField.allCases {
            fieldAgreements[field] = 0
            fieldTotals[field] = 0
        }

        // Compare each sentence
        let minCount = min(run1.sentences.count, run2.sentences.count)

        for i in 0..<minCount {
            let s1 = run1.sentences[i]
            let s2 = run2.sentences[i]

            for field in SentenceTelemetryField.allCases {
                fieldTotals[field, default: 0] += 1

                let val1 = s1.value(for: field)
                let val2 = s2.value(for: field)

                if val1 == val2 {
                    fieldAgreements[field, default: 0] += 1
                } else {
                    disagreements.append(SentenceDisagreement(
                        sentenceIndex: i,
                        sentenceText: String(s1.text.prefix(80)),
                        fieldName: field.displayName,
                        run1Value: val1,
                        run2Value: val2
                    ))
                }
            }
        }

        // Calculate per-field stability
        var fieldStability: [String: Double] = [:]
        for field in SentenceTelemetryField.allCases {
            let total = fieldTotals[field] ?? 0
            let agreed = fieldAgreements[field] ?? 0
            fieldStability[field.rawValue] = total > 0 ? Double(agreed) / Double(total) : 1.0
        }

        // Calculate overall stability
        let totalFields = Double(fieldStability.count)
        let overallStability = fieldStability.values.reduce(0, +) / totalFields

        return FidelityComparisonResult(
            run1: run1,
            run2: run2,
            overallStability: overallStability,
            fieldStability: fieldStability,
            disagreements: disagreements
        )
    }
}

// MARK: - Errors

enum SentenceTaggingError: LocalizedError {
    case invalidJSON(String)
    case parseError(String)
    case noTranscript
    case partialFailure(successes: Int, failures: [SentenceTaggingFailure])

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .noTranscript: return "Video has no transcript"
        case .partialFailure(let successes, let failures):
            return "Partial failure: \(successes) succeeded, \(failures.count) failed"
        }
    }
}

/// Error that carries debug context for troubleshooting
struct SentenceTaggingErrorWithContext: Error {
    let underlyingMessage: String
    let rawResponse: String
    let cleanedJSON: String
}

// MARK: - Failure Tracking

/// Captures details about a failed sentence tagging attempt for debugging
struct SentenceTaggingFailure: Identifiable {
    let id = UUID()
    let sentenceIndex: Int
    let sentenceText: String
    let rawResponse: String
    let cleanedJSON: String
    let errorMessage: String
    let timestamp: Date

    /// Format for copying to clipboard
    var debugDescription: String {
        """
        === FAILURE: Sentence \(sentenceIndex) ===
        Time: \(timestamp)
        Error: \(errorMessage)

        Original Sentence:
        \(sentenceText)

        Raw Response (first 500 chars):
        \(String(rawResponse.prefix(500)))

        Cleaned JSON:
        \(cleanedJSON)
        =====================================
        """
    }
}

/// Shared storage for recent failures (for debugging)
class SentenceTaggingDebugStore {
    static let shared = SentenceTaggingDebugStore()

    private let lock = NSLock()
    private var _failures: [SentenceTaggingFailure] = []

    var failures: [SentenceTaggingFailure] {
        lock.lock()
        defer { lock.unlock() }
        return _failures
    }

    func addFailure(_ failure: SentenceTaggingFailure) {
        lock.lock()
        _failures.append(failure)
        // Keep only last 100 failures
        if _failures.count > 100 {
            _failures.removeFirst(_failures.count - 100)
        }
        lock.unlock()
    }

    func clearFailures() {
        lock.lock()
        _failures.removeAll()
        lock.unlock()
    }

    /// Get all failures as a single copyable string
    var allFailuresText: String {
        lock.lock()
        defer { lock.unlock() }
        if _failures.isEmpty {
            return "No failures recorded."
        }
        return _failures.map { $0.debugDescription }.joined(separator: "\n\n")
    }
}
