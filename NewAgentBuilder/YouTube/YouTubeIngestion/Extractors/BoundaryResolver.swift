//
//  BoundaryResolver.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/23/26.
//

import Foundation

// MARK: - BoundaryResolver
// Converts LLM text boundaries to word indexes.
// LLM identifies boundaries semantically (quotes text), code locates them deterministically.

struct BoundaryResolver {

    // MARK: - Types

    struct ResolvedBoundary {
        let sectionIndex: Int
        let startWordIndex: Int
        let endWordIndex: Int
        let boundaryText: String      // What the LLM quoted (for auditing)
        let matchConfidence: Double   // 1.0 = exact match, <1.0 = fuzzy
    }

    struct ResolutionResult {
        let boundaries: [ResolvedBoundary]
        let totalWordsInTranscript: Int
        let coverageComplete: Bool    // Did we cover the entire transcript?
        let warnings: [String]
    }

    // MARK: - Main Resolution

    /// Resolve text boundaries to word indexes
    /// - Parameters:
    ///   - transcript: Full transcript text
    ///   - boundaryTexts: Array of boundary phrases in order (last ~15-20 words of each section)
    /// - Returns: ResolutionResult with resolved ranges, guaranteed contiguous
    static func resolve(
        transcript: String,
        boundaryTexts: [String]
    ) -> ResolutionResult {
        let words = tokenize(transcript)
        var results: [ResolvedBoundary] = []
        var warnings: [String] = []
        var searchStart = 0

        for (index, boundaryText) in boundaryTexts.enumerated() {
            // Find where this boundary phrase ends in the transcript
            let match = findPhraseEnd(
                in: words,
                phrase: boundaryText,
                searchAfter: searchStart
            )

            // Log warning if low confidence
            if match.confidence < 0.8 {
                let warning = "Low confidence match (\(String(format: "%.2f", match.confidence))) for section \(index): \"\(boundaryText.prefix(50))...\""
                warnings.append(warning)
                print("⚠️ \(warning)")
            }

            results.append(ResolvedBoundary(
                sectionIndex: index,
                startWordIndex: searchStart,
                endWordIndex: match.endIndex,
                boundaryText: boundaryText,
                matchConfidence: match.confidence
            ))

            // Next section starts immediately after this one
            searchStart = match.endIndex + 1
        }

        // Check coverage
        let totalWords = words.count
        let lastEnd = results.last?.endWordIndex ?? -1
        let coverageComplete = (lastEnd == totalWords - 1)

        if !coverageComplete && !boundaryTexts.isEmpty {
            let uncovered = totalWords - 1 - lastEnd
            let warning = "Coverage incomplete: \(uncovered) words at end of transcript not covered"
            warnings.append(warning)
            print("⚠️ \(warning)")
        }

        return ResolutionResult(
            boundaries: results,
            totalWordsInTranscript: totalWords,
            coverageComplete: coverageComplete,
            warnings: warnings
        )
    }

    /// Resolve with an implicit final section that goes to the end of transcript
    /// Use this when the LLM provides N-1 boundaries for N sections
    static func resolveWithFinalSection(
        transcript: String,
        boundaryTexts: [String]
    ) -> ResolutionResult {
        let words = tokenize(transcript)
        var results: [ResolvedBoundary] = []
        var warnings: [String] = []
        var searchStart = 0

        for (index, boundaryText) in boundaryTexts.enumerated() {
            let match = findPhraseEnd(
                in: words,
                phrase: boundaryText,
                searchAfter: searchStart
            )

            if match.confidence < 0.8 {
                let warning = "Low confidence match (\(String(format: "%.2f", match.confidence))) for section \(index): \"\(boundaryText.prefix(50))...\""
                warnings.append(warning)
                print("⚠️ \(warning)")
            }

            results.append(ResolvedBoundary(
                sectionIndex: index,
                startWordIndex: searchStart,
                endWordIndex: match.endIndex,
                boundaryText: boundaryText,
                matchConfidence: match.confidence
            ))

            searchStart = match.endIndex + 1
        }

        // Add final section that goes to end of transcript
        if searchStart < words.count {
            results.append(ResolvedBoundary(
                sectionIndex: boundaryTexts.count,
                startWordIndex: searchStart,
                endWordIndex: words.count - 1,
                boundaryText: "(final section - to end of transcript)",
                matchConfidence: 1.0
            ))
        }

        return ResolutionResult(
            boundaries: results,
            totalWordsInTranscript: words.count,
            coverageComplete: true,  // By design, final section goes to end
            warnings: warnings
        )
    }

    // MARK: - Phrase Finding

    private struct PhraseMatch {
        let endIndex: Int      // Word index where the phrase ends
        let confidence: Double // 0.0 to 1.0
    }

    /// Find where a phrase ends in the word array
    /// Uses sliding window with fuzzy matching
    private static func findPhraseEnd(
        in words: [String],
        phrase: String,
        searchAfter: Int
    ) -> PhraseMatch {
        let phraseWords = tokenize(phrase)

        guard !phraseWords.isEmpty else {
            return PhraseMatch(endIndex: searchAfter, confidence: 0.0)
        }

        let windowSize = phraseWords.count
        var bestMatch: PhraseMatch = PhraseMatch(endIndex: searchAfter + windowSize - 1, confidence: 0.0)

        // Can't search if not enough words remaining
        guard searchAfter + windowSize <= words.count else {
            print("⚠️ Not enough words remaining for phrase search")
            return PhraseMatch(endIndex: min(searchAfter + windowSize - 1, words.count - 1), confidence: 0.0)
        }

        // Sliding window search
        for i in searchAfter...(words.count - windowSize) {
            let windowWords = Array(words[i..<(i + windowSize)])
            let score = matchScore(phraseWords, windowWords)

            if score > bestMatch.confidence {
                bestMatch = PhraseMatch(
                    endIndex: i + windowSize - 1,  // End index of the matched phrase
                    confidence: score
                )
            }

            // Perfect match - stop searching
            if score >= 1.0 {
                break
            }
        }

        return bestMatch
    }

    // MARK: - Tokenization & Matching

    /// Tokenize text into normalized words for matching
    private static func tokenize(_ text: String) -> [String] {
        text.split(separator: " ")
            .map { normalizeWord(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Normalize a word for comparison
    /// Handles contractions, punctuation, case
    private static func normalizeWord(_ word: String) -> String {
        var normalized = word.lowercased()

        // Remove punctuation (but keep apostrophes for now)
        normalized = normalized.replacingOccurrences(
            of: "[^a-z0-9']",
            with: "",
            options: .regularExpression
        )

        // Normalize contractions
        normalized = normalized
            .replacingOccurrences(of: "'s", with: "s")
            .replacingOccurrences(of: "'t", with: "t")
            .replacingOccurrences(of: "'ll", with: "ll")
            .replacingOccurrences(of: "'re", with: "re")
            .replacingOccurrences(of: "'ve", with: "ve")
            .replacingOccurrences(of: "'d", with: "d")
            .replacingOccurrences(of: "'m", with: "m")
            .replacingOccurrences(of: "'", with: "")

        return normalized
    }

    /// Compare two word arrays, return 0-1 similarity
    private static func matchScore(_ phraseWords: [String], _ windowWords: [String]) -> Double {
        guard phraseWords.count == windowWords.count, !phraseWords.isEmpty else {
            return 0.0
        }

        var matches = 0
        for (a, b) in zip(phraseWords, windowWords) {
            if a == b {
                matches += 1
            }
        }

        return Double(matches) / Double(phraseWords.count)
    }

    // MARK: - Utilities

    /// Extract the text for a resolved boundary from the transcript
    static func extractText(from transcript: String, boundary: ResolvedBoundary) -> String {
        let words = transcript.split(separator: " ").map(String.init)
        guard boundary.startWordIndex >= 0,
              boundary.endWordIndex < words.count,
              boundary.startWordIndex <= boundary.endWordIndex else {
            return ""
        }
        return words[boundary.startWordIndex...boundary.endWordIndex].joined(separator: " ")
    }

    /// Validate that boundaries are contiguous and cover the transcript
    static func validate(_ result: ResolutionResult) -> (valid: Bool, issues: [String]) {
        var issues: [String] = []

        // Check for gaps
        for i in 0..<(result.boundaries.count - 1) {
            let current = result.boundaries[i]
            let next = result.boundaries[i + 1]

            if current.endWordIndex + 1 != next.startWordIndex {
                issues.append("Gap between section \(i) and \(i+1): ends at \(current.endWordIndex), next starts at \(next.startWordIndex)")
            }
        }

        // Check first section starts at 0
        if let first = result.boundaries.first, first.startWordIndex != 0 {
            issues.append("First section doesn't start at word 0 (starts at \(first.startWordIndex))")
        }

        // Check coverage
        if !result.coverageComplete {
            issues.append("Transcript not fully covered")
        }

        // Check for low confidence matches
        let lowConfidence = result.boundaries.filter { $0.matchConfidence < 0.7 }
        if !lowConfidence.isEmpty {
            issues.append("\(lowConfidence.count) sections have low confidence matches (<0.7)")
        }

        return (issues.isEmpty, issues)
    }
}
