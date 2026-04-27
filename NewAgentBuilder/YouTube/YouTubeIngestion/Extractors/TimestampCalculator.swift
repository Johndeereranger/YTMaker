//
//  TimestampCalculator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//
import Foundation
import SwiftUI

import Foundation
import SwiftUI

// MARK: - Timestamp Calculator
struct TimestampCalculator {
    let transcript: String
    let wordsPerSecond: Double
    let durationSeconds: Int   // ✅ store parsed duration for later use

    init(transcript: String, duration: String) {
        let totalWords = transcript.split(separator: " ").count
        let totalSeconds = Self.parseDuration(duration)

        self.transcript = transcript
        self.durationSeconds = totalSeconds
        self.wordsPerSecond = totalSeconds > 0 ? Double(totalWords) / Double(totalSeconds) : 0

        print("📊 TIMESTAMP CALCULATOR INIT:")
        print("  Duration string: '\(duration)'")
        print("  Parsed seconds: \(totalSeconds)")
        print("  Total words: \(totalWords)")
        print("  Words per second: \(wordsPerSecond)")
    }

    func calculateTimestamp(for textSnippet: String) -> Int {
        let wordPosition = findWordPosition(textSnippet, in: transcript)

        guard wordsPerSecond > 0 else {
            print("⚠️ WARNING: wordsPerSecond is 0, cannot calculate timestamp")
            return 0
        }

        let timestampDouble = Double(wordPosition) / wordsPerSecond

        guard timestampDouble.isFinite else {
            print("⚠️ WARNING: timestamp calculation resulted in NaN/Infinity")
            return 0
        }

        return max(0, Int(timestampDouble))
    }

    private func findWordPosition(_ snippet: String, in fullText: String) -> Int {
        let words = fullText.split(separator: " ").map { String($0) }
        let snippetWords = snippet.split(separator: " ").map { String($0) }

        guard !snippetWords.isEmpty else { return 0 }

        for i in 0...(words.count - snippetWords.count) {
            var match = true
            for j in 0..<snippetWords.count {
                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if word1 != word2 {
                    match = false
                    break
                }
            }
            if match { return i }
        }

        return fuzzySearch(snippetWords, in: words)
    }

    private func fuzzySearch(_ snippetWords: [String], in words: [String]) -> Int {
        var bestMatch = 0
        var bestScore = 0

        for i in 0...(words.count - snippetWords.count) {
            var score = 0
            for j in 0..<snippetWords.count {
                let word1 = words[i + j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                let word2 = snippetWords[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if word1 == word2 { score += 1 }
            }
            if score > bestScore {
                bestScore = score
                bestMatch = i
            }
        }

        return bestMatch
    }

    static func parseDuration(_ duration: String) -> Int {
        if duration.hasPrefix("PT") {
            let timeString = duration.dropFirst(2)
            var hours = 0, minutes = 0, seconds = 0
            var currentValue = ""

            for char in timeString {
                if char.isNumber {
                    currentValue.append(char)
                } else if char == "H" {
                    hours = Int(currentValue) ?? 0
                    currentValue = ""
                } else if char == "M" {
                    minutes = Int(currentValue) ?? 0
                    currentValue = ""
                } else if char == "S" {
                    seconds = Int(currentValue) ?? 0
                    currentValue = ""
                }
            }

            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            print("  Parsed ISO 8601: \(hours)h \(minutes)m \(seconds)s = \(totalSeconds)s")
            return totalSeconds
        }

        let components = duration.split(separator: ":")
        if components.count == 2 {
            let minutes = Int(components[0]) ?? 0
            let seconds = Int(components[1]) ?? 0
            return minutes * 60 + seconds
        } else if components.count == 3 {
            let hours = Int(components[0]) ?? 0
            let minutes = Int(components[1]) ?? 0
            let seconds = Int(components[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        }

        print("⚠️ WARNING: Could not parse duration '\(duration)'")
        return 0
    }
}

// MARK: - Enhanced TimestampCalculator
extension TimestampCalculator {
    /// Calculate timestamp from word index (0-based)
//    func calculateTimestampFromWordIndex(_ wordIndex: Int) -> Int {
//        let words = transcript.split(whereSeparator: { $0.isWhitespace })
//        guard wordIndex >= 0 else { return 0 }
//        guard wordIndex < words.count else { return durationSeconds }
//
//        let proportion = Double(wordIndex) / Double(words.count)
//        return Int(proportion * Double(durationSeconds))
//    }
//    
//    func calculateTimestampFromWordIndex(_ wordIndex: Int) -> Int {
//        guard wordsPerSecond > 0 else {
//            print("⚠️ WARNING: wordsPerSecond is 0, cannot calculate timestamp")
//            return 0
//        }
//        
//        let timestampDouble = Double(wordIndex) / wordsPerSecond
//        
//        guard timestampDouble.isFinite else {
//            print("⚠️ WARNING: timestamp calculation resulted in NaN/Infinity")
//            return 0
//        }
//        
//        let timestamp = Int(timestampDouble)
//        return max(0, timestamp)
//    }
    func calculateTimestampFromWordIndex(_ wordIndex: Int) -> Int {
        guard wordsPerSecond > 0 else {
            print("⚠️ WARNING: wordsPerSecond is 0, cannot calculate timestamp")
            return 0
        }
        
        // Lower bound
        guard wordIndex >= 0 else { return 0 }
        
        let timestampDouble = Double(wordIndex) / wordsPerSecond
        
        guard timestampDouble.isFinite else {
            print("⚠️ WARNING: timestamp calculation resulted in NaN/Infinity")
            return 0
        }
        
        let timestamp = Int(timestampDouble)
        
        // Upper bound - don't exceed video duration
        return min(max(0, timestamp), durationSeconds)
    }
}
