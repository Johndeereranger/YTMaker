//
//  SentenceParser.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/4/26.
//

import Foundation

enum SentenceParser {

    static func parse(_ text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if looksPreFormatted(lines) {
            return lines
        }

        let normalizedText = normalizeTranscriptArtifacts(in: lines.joined(separator: " "))
        let transcriptChunks = splitOnTranscriptSeparators(in: normalizedText)
        return transcriptChunks.flatMap(splitSentences)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitSentences(in text: String) -> [String] {
        let (protectedText, placeholderMap) = protectTokens(in: text)
        let pattern = #"([.!?]+["'”]?)\s+(?=(?:["“(\[])?(?:[A-Z]|\d))"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [restoreTokens(in: text, using: placeholderMap)]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let ns = protectedText as NSString
        let matches = regex.matches(in: protectedText, range: NSRange(location: 0, length: ns.length))

        var sentences: [String] = []
        var lastIndex = 0

        for match in matches {
            let endOfPunctuation = match.range(at: 1).location + match.range(at: 1).length
            let sentence = ns.substring(with: NSRange(location: lastIndex, length: endOfPunctuation - lastIndex))
            sentences.append(restoreTokens(in: sentence, using: placeholderMap))
            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < ns.length {
            sentences.append(restoreTokens(in: ns.substring(from: lastIndex), using: placeholderMap))
        }

        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeTranscriptArtifacts(in text: String) -> String {
        let patterns = [
            #"\[(?:\d+)\]"#,
            #"\[(?:[A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*){0,2}|[A-Z]{2,})\]"#,
            #"\([^)]*?(?:music|ticking|humming|roaring|blaring|siren|clanging|crackling|clacking|whooshing|rasping|rumbling|chirping|chiming|clamoring|mooing|beeping|laughing|applause|cheering|crowd cheering|audience laughs|waves crashing|machine whirring|gasps|speaking foreign language|dramatic music|suspenseful sting|music swells|music intensifies|intense music(?:\s+continues)?|PA\s[^)]*)\)"#,
            #"♪[^♪]*♪"#
        ]

        var normalized = text
        for pattern in patterns {
            normalized = replacingMatches(in: normalized, pattern: pattern, with: " ")
        }

        normalized = replacingMatches(in: normalized, pattern: #"\s+"#, with: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitOnTranscriptSeparators(in text: String) -> [String] {
        let pattern = #"([.!?]+["'”]?)\s+-\s+(?=(?:["“(\[])?(?:[A-Z]|\d))"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        guard !matches.isEmpty else {
            return [text]
        }

        var chunks: [String] = []
        var lastIndex = 0

        for match in matches {
            let splitLocation = match.range(at: 1).location + match.range(at: 1).length
            let chunk = ns.substring(with: NSRange(location: lastIndex, length: splitLocation - lastIndex))
            let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedChunk.isEmpty {
                chunks.append(trimmedChunk)
            }
            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < ns.length {
            let tail = ns.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                chunks.append(tail)
            }
        }

        return chunks
    }

    private static func replacingMatches(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func looksPreFormatted(_ lines: [String]) -> Bool {
        guard lines.count > 1 else { return false }

        return lines.allSatisfy {
            $0.count > 10 &&
            ($0.last == "." || $0.last == "!" || $0.last == "?") &&
            countSentenceEndings(in: $0) == 1
        }
    }

    private static func countSentenceEndings(in text: String) -> Int {
        text.filter { ".!?".contains($0) }.count
    }

    private static func protectTokens(in text: String) -> (String, [String: String]) {
        var output = text
        var map: [String: String] = [:]
        var index = 0

        let initialPattern = #"\b(?:[A-Z]\.\s*){1,3}(?=[A-Z][a-z])"#
        if let initialRegex = try? NSRegularExpression(pattern: initialPattern) {
            let matches = initialRegex.matches(in: output, range: NSRange(output.startIndex..., in: output))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                let value = String(output[range])
                let key = "§INITIAL\(index)§"
                map[key] = value
                output.replaceSubrange(range, with: key)
                index += 1
            }
        }

        let abbreviations = [
            "Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Sr.", "Jr.",
            "U.S.", "U.K.", "U.N.", "E.U.", "A.M.", "P.M.",
            "Inc.", "Ltd.", "Corp.", "Co.", "vs.", "etc.", "i.e.", "e.g.",
            "St.", "Ave.", "Blvd.", "Rd.", "Mt.", "Ft."
        ]

        for abbreviation in abbreviations where output.contains(abbreviation) {
            let key = "§ABBR\(index)§"
            map[key] = abbreviation
            output = output.replacingOccurrences(of: abbreviation, with: key)
            index += 1
        }

        let decimalPattern = #"(\d+\.\d+)"#
        let regex = try? NSRegularExpression(pattern: decimalPattern)
        regex?.matches(in: output, range: NSRange(output.startIndex..., in: output))
            .reversed()
            .forEach {
                guard let range = Range($0.range, in: output) else { return }
                let value = String(output[range])
                let key = "§NUM\(index)§"
                map[key] = value
                output.replaceSubrange(range, with: key)
                index += 1
            }

        return (output, map)
    }

    private static func restoreTokens(in text: String, using map: [String: String]) -> String {
        var restored = text
        for (key, value) in map {
            restored = restored.replacingOccurrences(of: key, with: value)
        }
        return restored
    }
}
