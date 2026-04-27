//
//  SoundBeatParser.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/3/25.
//
import Foundation

enum SoundBeatParser {
    static func parse(
        beatRaw: String,
        promptRaw: String,
        matchingRaw: String,
        scriptId: UUID
    ) -> [SoundBeat] {
        let beatLines = beatRaw.components(separatedBy: .newlines)
        let promptLines = promptRaw.components(separatedBy: .newlines)
        let matchingLines = matchingRaw.components(separatedBy: .newlines)
        
        var beats: [SoundBeat] = []
        
        for (index, line) in beatLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let order = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            
            var generatedPrompt: String?
            if index < promptLines.count {
                let promptLine = promptLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let promptParts = promptLine.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
                if promptParts.count == 2 {
                    generatedPrompt = promptParts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            
            var selectedImagePromptId: String?
            var needsImageGeneration = true
            if index < matchingLines.count {
                let matchingLine = matchingLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let matchParts = matchingLine.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
                if matchParts.count == 2 {
                    let matchText = matchParts[1].trimmingCharacters(in: .whitespaces)
                    if !matchText.contains("❌ No match") {
                        if let idRange = matchText.range(of: "Match: ") {
                            selectedImagePromptId = String(matchText[idRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        } else if matchText.hasPrefix("✅") {
                            selectedImagePromptId = matchText.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        } else {
                            selectedImagePromptId = matchText
                        }
                        if let id = selectedImagePromptId, !id.isEmpty {
                            needsImageGeneration = false
                        }
                    }
                }
            }
            
            beats.append(SoundBeat(
                scriptId: scriptId,
                order: order,
                text: text,
                generatedPrompt: generatedPrompt,
                selectedImagePromptId: selectedImagePromptId,
                matchedImageURL: nil,
                needsImageGeneration: needsImageGeneration
            ))
        }
        
        return beats.sorted(by: { $0.order < $1.order })
    }
    
    static func parseShort(
        beatRaw: String,
        promptRaw: String,
        scriptId: UUID
    ) -> [SoundBeat] {
        let beatLines = beatRaw.components(separatedBy: .newlines)
        let promptLines = promptRaw.components(separatedBy: .newlines)
        
        var beats: [SoundBeat] = []
        
        for (index, line) in beatLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Parse order + beat text
            let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let order = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            
            // Parse generated prompt (always try to get this)
            var generatedPrompt: String?
            if index < promptLines.count {
                let promptLine = promptLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let promptParts = promptLine.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
                if promptParts.count == 2 {
                    generatedPrompt = promptParts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            
            
            beats.append(SoundBeat(
                scriptId: scriptId,
                order: order,
                text: text,
                generatedPrompt: generatedPrompt,
                selectedImagePromptId: nil,
                matchedImageURL: nil,
                needsImageGeneration: true,
                localAudioFilePath: nil
            ))
        }
        
        return beats.sorted(by: { $0.order < $1.order })
    }
    
    static func parseWithRankedMatch(
        beatRaw: String,
        promptRaw: String,
        matchingRaw: String,
        scriptId: UUID
    ) -> [SoundBeat] {
        let beatLines = beatRaw.components(separatedBy: .newlines)
        let promptLines = promptRaw.components(separatedBy: .newlines)
        let matchingLines = matchingRaw.components(separatedBy: .newlines)
        
        var beats: [SoundBeat] = []
        
        for (index, line) in beatLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Parse order + beat text
            let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let order = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            
            // Parse generated prompt (always try to get this)
            var generatedPrompt: String?
            if index < promptLines.count {
                let promptLine = promptLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let promptParts = promptLine.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
                if promptParts.count == 2 {
                    generatedPrompt = promptParts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Parse matching line with proper defaults
            var systemMatchedPromptId: String?
            var systemMatchStrength: MatchStrength = .none  // Default to none
            var selectedImagePromptId: String?
            var needsImageGeneration = true  // Default to true
            
            if index < matchingLines.count {
                let matchLine = matchingLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = parseMatchLine(matchLine) {
                    systemMatchedPromptId = match.promptId
                    systemMatchStrength = match.strength
                    
                    // Use the autoSelect property to determine selection
                    if systemMatchStrength.autoSelect {
                        selectedImagePromptId = systemMatchedPromptId
                        needsImageGeneration = false
                    }
                    // If not auto-selected, keep defaults (nil, true)
                } else {
                    print("No match")
                }
            } else {
                
            }
            
            beats.append(SoundBeat(
                scriptId: scriptId,
                order: order,
                text: text,
                generatedPrompt: generatedPrompt,
                selectedImagePromptId: selectedImagePromptId,
                matchedImageURL: nil,
                needsImageGeneration: needsImageGeneration,
                localAudioFilePath: nil
            ))
        }
        
        return beats.sorted(by: { $0.order < $1.order })
        
    }
    private static func parseMatchLine(_ line: String) -> (strength: MatchStrength, promptId: String)? {
        // Handle NO MATCH case first
        if line.contains("❌") || line.contains("NO MATCH") {
            return (.none, "")
        }
        
        // Map emojis to match strengths
        let strengthMap: [(emoji: String, strength: MatchStrength)] = [
            ("🟢", .strong),
            ("🟡", .moderate),
            ("🟠", .weak),
            ("🔴", .none)
        ]
        
        for (emoji, strength) in strengthMap {
            if let range = line.range(of: emoji) {
                let remaining = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                // Extract ID - look for patterns like:
                // "🟢 EXCELLENT: [15] Description..."
                // "🟡 GOOD: 15 Description..."
                // "🟠 MODERATE: PromptXYZ123 Description..."
                
                if let bracketMatch = remaining.range(of: "\\[\\d+\\]", options: .regularExpression) {
                    // Extract number from [15]
                    let bracket = String(remaining[bracketMatch])
                    let id = String(bracket.dropFirst().dropLast()) // Remove [ ]
                    return (strength, id)
                } else {
                    // Look for first word/token after confidence level
                    let components = remaining.split(separator: " ")
                    if components.count >= 2 {
                        // Skip confidence word (EXCELLENT, GOOD, etc.), take next token
                        let id = String(components[1])
                        return (strength, id)
                    }
                }
            }
        }
        
        return nil
    }
}
