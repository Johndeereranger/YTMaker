//
//  SlotPreFilter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//

import Foundation

// MARK: - Pre-Filter Result

struct PreFilterResult {
    let originalSentences: [String]
    let filteredSentences: [String]
    let actions: [PreFilterAction]
    /// Maps each filtered sentence index → array of original indices that contributed to it
    let originMap: [Int: [Int]]
}

enum PreFilterAction {
    case removedJunk(originalIndex: Int, text: String)
    case mergedFragment(originalIndex: Int, text: String, mergedIntoOriginal: Int)
    case taggedReactionBeat(originalIndex: Int, text: String)
    case taggedVisualAnchor(originalIndex: Int, text: String)

    var description: String {
        switch self {
        case .removedJunk(_, let text):
            return "Removed junk: \"\(text)\""
        case .mergedFragment(_, let text, let target):
            return "Merged fragment \"\(text)\" into sentence \(target + 1)"
        case .taggedReactionBeat(_, let text):
            return "Tagged reaction_beat: \"\(text)\""
        case .taggedVisualAnchor(_, let text):
            return "Tagged visual_anchor: \"\(text)\""
        }
    }
}

// MARK: - Pre-Filter Logic

enum SlotPreFilter {

    /// Pre-filter sentences after SentenceParser.parse() + stripParentheticals().
    /// Removes junk (bare punctuation), merges orphaned fragments, tags interjections/deictic phrases.
    static func filter(_ sentences: [String]) -> PreFilterResult {
        guard !sentences.isEmpty else {
            return PreFilterResult(originalSentences: [], filteredSentences: [], actions: [], originMap: [:])
        }

        var actions: [PreFilterAction] = []

        // Pass 1: Classify each sentence
        enum Classification {
            case junk
            case fragment
            case reactionBeat
            case visualAnchor
            case normal
        }

        let classifications: [Classification] = sentences.enumerated().map { idx, sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)

            // Junk: no alphabetic content at all
            if isJunk(trimmed) {
                return .junk
            }

            // Reaction beat: standalone interjection
            if isReactionBeat(trimmed) {
                return .reactionBeat
            }

            // Visual anchor: standalone deictic phrase
            if isVisualAnchor(trimmed) {
                return .visualAnchor
            }

            // Fragment: short, starts with lowercase (continuation of bad split)
            if isFragment(trimmed) {
                return .fragment
            }

            return .normal
        }

        // Pass 2: Build output by applying merge rules
        // We build an array of "slots" — each slot is either a single sentence or a merged composite
        struct OutputSlot {
            var text: String
            var originalIndices: [Int]
        }

        var slots: [OutputSlot] = []

        for (idx, classification) in classifications.enumerated() {
            let text = sentences[idx].trimmingCharacters(in: .whitespacesAndNewlines)

            switch classification {
            case .junk:
                actions.append(.removedJunk(originalIndex: idx, text: text))
                // Skip entirely — don't add to slots

            case .fragment:
                // Merge into previous slot if available, otherwise next
                if !slots.isEmpty {
                    let targetOriginal = slots[slots.count - 1].originalIndices.first ?? idx
                    actions.append(.mergedFragment(originalIndex: idx, text: text, mergedIntoOriginal: targetOriginal))
                    slots[slots.count - 1].text += " " + text
                    slots[slots.count - 1].originalIndices.append(idx)
                } else {
                    // No previous — just add as normal, it'll merge forward when next sentence appears
                    // Actually, hold it and merge into next on next iteration
                    slots.append(OutputSlot(text: text, originalIndices: [idx]))
                    // Mark for forward merge — we'll handle this after the loop
                }

            case .reactionBeat:
                actions.append(.taggedReactionBeat(originalIndex: idx, text: text))
                slots.append(OutputSlot(text: text, originalIndices: [idx]))

            case .visualAnchor:
                actions.append(.taggedVisualAnchor(originalIndex: idx, text: text))
                slots.append(OutputSlot(text: text, originalIndices: [idx]))

            case .normal:
                slots.append(OutputSlot(text: text, originalIndices: [idx]))
            }
        }

        // Handle edge case: if first slot was a fragment with no previous, merge it into the next
        if slots.count >= 2,
           let firstOrigIdx = slots[0].originalIndices.first,
           classifications[firstOrigIdx] == .fragment {
            // Prepend first slot's text to second slot
            slots[1].text = slots[0].text + " " + slots[1].text
            slots[1].originalIndices = slots[0].originalIndices + slots[1].originalIndices
            // Update the action to point to the correct target
            if let actionIdx = actions.firstIndex(where: {
                if case .mergedFragment(let origIdx, _, _) = $0, origIdx == firstOrigIdx { return true }
                return false
            }) {
                let targetOriginal = slots[1].originalIndices.last ?? firstOrigIdx
                actions[actionIdx] = .mergedFragment(originalIndex: firstOrigIdx, text: sentences[firstOrigIdx], mergedIntoOriginal: targetOriginal)
            }
            slots.removeFirst()
        }

        // Build origin map and output
        var originMap: [Int: [Int]] = [:]
        let filteredSentences = slots.enumerated().map { filteredIdx, slot -> String in
            originMap[filteredIdx] = slot.originalIndices
            return slot.text
        }

        return PreFilterResult(
            originalSentences: sentences,
            filteredSentences: filteredSentences,
            actions: actions,
            originMap: originMap
        )
    }

    // MARK: - Detection Heuristics

    /// Junk: empty, whitespace-only, or contains no alphabetic characters (bare punctuation, periods, dashes)
    static func isJunk(_ sentence: String) -> Bool {
        guard !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let stripped = sentence.replacingOccurrences(of: #"[^a-zA-Z]"#, with: "", options: .regularExpression)
        return stripped.isEmpty
    }

    /// Fragment: short continuation from a bad sentence split.
    /// - Word count ≤ 4
    /// - Starts with lowercase letter (indicates it was orphaned from previous sentence)
    /// - Not an interjection or deictic phrase
    static func isFragment(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let words = trimmed.split(separator: " ")
        guard words.count <= 4 else { return false }

        // Must start with lowercase (continuation indicator)
        guard let first = trimmed.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else {
            return false
        }

        // Exclude if it's a recognized interjection or deictic
        if isReactionBeat(trimmed) || isVisualAnchor(trimmed) { return false }

        return true
    }

    /// Reaction beat: standalone interjection / performative reaction
    static func isReactionBeat(_ sentence: String) -> Bool {
        let pattern = #"^(Oh|Wow|Yeah|Yep|Nope|Right|Sure|Okay|OK|Man|Dude|Hmm|Huh|Ah|Whoa|No|Yes|Well|Check)[,!.]*\s*$"#
        return sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Visual anchor: standalone deictic reference pointing to visuals
    static func isVisualAnchor(_ sentence: String) -> Bool {
        let pattern = #"^(This|That|These|Those|Here|There|Look at (this|that)|Check this out)[.!]*\s*$"#
        return sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
