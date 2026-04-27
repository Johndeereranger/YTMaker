//
//  SlotPostProcessor.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//

import Foundation

// MARK: - Post-Processed Annotation

struct PostProcessedAnnotation {
    let rawPhrases: [SentencePhrase]
    let processedPhrases: [SentencePhrase]
    let rawSignature: String
    let processedSignature: String
    let mergeActions: [OtherMergeAction]
}

struct OtherMergeAction {
    let otherPhraseText: String
    let mergedIntoRole: String
    let direction: String  // "previous", "next", or "kept" (not merged)
}

// MARK: - Post-Processor Logic

enum SlotPostProcessor {

    /// Post-process an array of SlotAnnotationResults by merging "other" phrases into adjacent phrases.
    /// Returns one PostProcessedAnnotation per input result.
    static func process(_ results: [SlotAnnotationResult]) -> [PostProcessedAnnotation] {
        results.map { processOne($0) }
    }

    /// Process a single sentence's annotation: merge "other" phrases into neighbors.
    private static func processOne(_ result: SlotAnnotationResult) -> PostProcessedAnnotation {
        let rawPhrases = result.phrases
        let rawSignature = result.slotSequence.joined(separator: "|")

        guard rawPhrases.count > 1 else {
            // Single phrase or empty — nothing to merge
            return PostProcessedAnnotation(
                rawPhrases: rawPhrases,
                processedPhrases: rawPhrases,
                rawSignature: rawSignature,
                processedSignature: rawSignature,
                mergeActions: []
            )
        }

        // Work with mutable copies
        var phrases = rawPhrases.map { MutablePhrase(text: $0.text, role: $0.role) }
        var mergeActions: [OtherMergeAction] = []

        // Single left-to-right pass: mark "other" phrases for merging
        // We collect merge instructions first, then apply them
        struct MergeInstruction {
            let sourceIndex: Int
            let targetIndex: Int
            let direction: String
        }

        var instructions: [MergeInstruction] = []

        for i in 0..<phrases.count {
            guard phrases[i].role == "other" else { continue }

            let wordCount = phrases[i].text.split(separator: " ").count

            // Skip merge if "other" phrase > 8 words (genuinely uncategorized)
            if wordCount > 8 {
                mergeActions.append(OtherMergeAction(
                    otherPhraseText: phrases[i].text,
                    mergedIntoRole: "other",
                    direction: "kept"
                ))
                continue
            }

            // Determine merge direction
            if i == 0 {
                // First phrase → merge into next
                if i + 1 < phrases.count && phrases[i + 1].role != "empty_connector" {
                    instructions.append(MergeInstruction(sourceIndex: i, targetIndex: i + 1, direction: "next"))
                } else {
                    mergeActions.append(OtherMergeAction(
                        otherPhraseText: phrases[i].text,
                        mergedIntoRole: "other",
                        direction: "kept"
                    ))
                }
            } else if i == phrases.count - 1 {
                // Last phrase → merge into previous
                if phrases[i - 1].role != "empty_connector" {
                    instructions.append(MergeInstruction(sourceIndex: i, targetIndex: i - 1, direction: "previous"))
                } else {
                    mergeActions.append(OtherMergeAction(
                        otherPhraseText: phrases[i].text,
                        mergedIntoRole: "other",
                        direction: "kept"
                    ))
                }
            } else {
                // Middle phrase → prefer previous, fallback to next
                if phrases[i - 1].role != "empty_connector" {
                    instructions.append(MergeInstruction(sourceIndex: i, targetIndex: i - 1, direction: "previous"))
                } else if i + 1 < phrases.count && phrases[i + 1].role != "empty_connector" {
                    instructions.append(MergeInstruction(sourceIndex: i, targetIndex: i + 1, direction: "next"))
                } else {
                    mergeActions.append(OtherMergeAction(
                        otherPhraseText: phrases[i].text,
                        mergedIntoRole: "other",
                        direction: "kept"
                    ))
                }
            }
        }

        // Apply merge instructions (mark sources for removal)
        var removedIndices: Set<Int> = []

        for instruction in instructions {
            let source = phrases[instruction.sourceIndex]
            let target = phrases[instruction.targetIndex]

            // Append source text to target
            if instruction.direction == "previous" {
                phrases[instruction.targetIndex].text = target.text + " " + source.text
            } else {
                phrases[instruction.targetIndex].text = source.text + " " + target.text
            }

            removedIndices.insert(instruction.sourceIndex)

            mergeActions.append(OtherMergeAction(
                otherPhraseText: source.text,
                mergedIntoRole: target.role,
                direction: instruction.direction
            ))
        }

        // Build processed phrases (excluding removed)
        let processedPhrases: [SentencePhrase] = phrases.enumerated().compactMap { idx, phrase in
            guard !removedIndices.contains(idx) else { return nil }
            return SentencePhrase(text: phrase.text, role: phrase.role)
        }

        let processedSignature = processedPhrases.map(\.role).joined(separator: "|")

        return PostProcessedAnnotation(
            rawPhrases: rawPhrases,
            processedPhrases: processedPhrases,
            rawSignature: rawSignature,
            processedSignature: processedSignature,
            mergeActions: mergeActions
        )
    }
}

// MARK: - Internal Mutable Phrase

private struct MutablePhrase {
    var text: String
    var role: String
}
