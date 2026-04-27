//
//  BeatPromptEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//

import Foundation
/*
// A1b: Beat Boundary Extraction Engine (SIMPLIFIED - boundaries only)
struct BeatPromptEngineOLd {
    let video: YouTubeVideo
    let section: SectionData
    let sectionIndex: Int
    
    func generatePromptOld() -> String {
        guard let transcript = video.transcript else {
            return "⚠️ No transcript available"
        }
        
        return """
You are extracting beat boundaries from a section. DO NOT analyze meaning - just identify WHERE beats are.

SECTION DATA:
ID: \(section.id)
Role: \(section.role)
Time Range: \(formatSeconds(section.timeRange.start)) - \(formatSeconds(section.timeRange.end))

FULL TRANSCRIPT:
\(transcript)

TASK: Identify beat boundaries ONLY. No analysis, no interpretation - just boundaries.

For this \(section.role) section, identify 2-8 beats:

1. BEAT IDENTIFICATION
   - beatId: "section_\(sectionIndex + 1)_\(section.role.lowercased())_b1", "b2", etc.
   - type: TEASE, QUESTION, PROMISE, DATA, STORY, AUTHORITY, SYNTHESIS, TURN, REFRAME, CALLBACK, PRINCIPLE, CLIP-REACTION, COUNTER-EXAMPLE, ANALOGY

2. TEXT BOUNDARIES (EXACT anchoring only)
   - text: COMPLETE exact text of this beat from transcript
   - startWordIndex: Word position where beat starts in FULL transcript (0-indexed)
   - endWordIndex: Word position where beat ends in FULL transcript (0-indexed)

OUTPUT FORMAT (strict JSON):
{
  "sectionId": "\(section.id)",
  "beats": [
    {
      "beatId": "section_1_hook_b1",
      "type": "TEASE",
      "text": "Complete exact text of the beat from transcript...",
      "startWordIndex": 0,
      "endWordIndex": 41
    }
  ]
}

BEAT TYPES EXPLAINED:
- TEASE: Create curiosity/tension without revealing
- QUESTION: Rhetorical or genuine question to audience
- PROMISE: Explicit statement of what you'll deliver
- DATA: Statistics, facts, numbers, measurements
- STORY: Narrative example, case study, anecdote
- AUTHORITY: Expert quote, study citation, credentials
- SYNTHESIS: "Here's what this means" / interpretation
- TURN: Subvert expectation, reveal hidden truth
- REFRAME: Shift perspective on established point
- CALLBACK: Reference earlier point for payoff
- PRINCIPLE: State general rule or pattern
- CLIP-REACTION: Narrate/react to visual evidence
- COUNTER-EXAMPLE: Show exception that proves rule
- ANALOGY: Explain via comparison/metaphor

CRITICAL REQUIREMENTS:
1. Word indexes must be accurate - count words from START of full transcript
2. Text must be EXACT from transcript - no paraphrasing
3. Each beat must have clear boundaries (no overlap)
4. Beats must cover the entire section (no gaps)
5. Return ONLY valid JSON, no markdown formatting
6. DO NOT include: function, whyNow, tempo, anchors, transitions - BOUNDARIES ONLY

VALIDATION:
- Beat count: 2-8 beats per section
- Coverage: All section text assigned to a beat
- Boundaries: No overlapping word indexes
"""
    }
    
    func generatePrompt() -> String {
        guard let transcript = video.transcript else {
            return "⚠️ No transcript available"
        }
        let beatIdPrefix = "\(video.videoId)_sect_\(sectionIndex + 1)_\(section.role.lowercased())"
        
        return """
    You are extracting beats from a section with essential fields for clustering analysis.

    SECTION DATA:
    ID: \(section.id)
    Role: \(section.role)
    Time Range: \(formatSeconds(section.timeRange.start)) - \(formatSeconds(section.timeRange.end))

    FULL TRANSCRIPT:
    \(transcript)

    TASK: Identify 2-8 beats with boundaries AND essential clustering fields.

    OUTPUT FORMAT (strict JSON):
    {
      "sectionId": "\(video.videoId)_\(section.id)",
      "beats": [
        {
          "beatId": "\(beatIdPrefix)_b1",
          "type": "TEASE",
          "text": "Complete exact text of the beat from transcript...",
          "startWordIndex": 0,
          "endWordIndex": 41,
          "stance": "neutral",
          "tempo": "fast",
          "formality": 5,
          "questionCount": 0,
          "containsAnchor": false,
          "anchorText": "",
          "anchorFunction": "none",
          "proofMode": "none"
        }
      ]
    }

    BEAT TYPES:
    - TEASE: Create curiosity/tension without revealing
    - QUESTION: Rhetorical or genuine question to audience
    - PROMISE: Explicit statement of what you'll deliver
    - DATA: Statistics, facts, numbers, measurements
    - STORY: Narrative example, case study, anecdote
    - AUTHORITY: Expert quote, study citation, credentials
    - SYNTHESIS: "Here's what this means" / interpretation
    - TURN: Subvert expectation, reveal hidden truth
    - REFRAME: Shift perspective on established point
    - CALLBACK: Reference earlier point for payoff
    - PRINCIPLE: State general rule or pattern
    - CLIP-REACTION: Narrate/react to visual evidence
    - COUNTER-EXAMPLE: Show exception that proves rule
    - ANALOGY: Explain via comparison/metaphor

    FIELD DEFINITIONS:
    - stance: "critical" | "neutral" | "playful" | "helpful" - emotional tone of the beat
    - tempo: "fast" | "steady" | "slow_build" - pacing/energy level
    - formality: 1-10 scale (1=very casual, 10=very formal)
    - questionCount: number of questions in this beat (0 if none)
    - containsAnchor: true if beat has a distinctive reusable phrase
    - anchorText: the distinctive phrase if containsAnchor=true, else ""
    - anchorFunction: "opener" | "turn" | "proofFrame" | "none"
    - proofMode: "none" | "stat" | "anecdote" | "authority" | "demo" | "logic"

    CRITICAL REQUIREMENTS:
    1. Word indexes must be accurate - count words from START of full transcript
    2. Text must be EXACT from transcript - no paraphrasing
    3. Each beat must have clear boundaries (no overlap)
    4. Beats must cover the entire section (no gaps)
    5. Return ONLY valid JSON, no markdown formatting
    6. All 12 fields required per beat - use defaults if uncertain

    VALIDATION:
    - Beat count: 2-8 beats per section
    - Coverage: All section text assigned to a beat
    - Boundaries: No overlapping word indexes
    """
    }
    func parseResponse(_ jsonString: String) throws -> BeatResponse {
        print("\n")
        print("========================================")
        print("🎵 STARTING BEAT JSON PARSING")
        print("========================================")
        print("Section: \(section.id) (\(section.role))")
        
        print("\n📥 RAW BEAT JSON RESPONSE:")
        print("Length: \(jsonString.count) characters")
        print("First 300 chars: \(String(jsonString.prefix(300)))")
        if jsonString.count > 300 {
            print("Last 200 chars: \(String(jsonString.suffix(200)))")
        }
        
        // Clean JSON
        var cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("\n🧹 CLEANING BEAT JSON...")
        
        if cleanJSON.hasPrefix("```json") {
            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ Removed markdown fences")
        }
        
        // Replace smart quotes with straight quotes
        cleanJSON = cleanJSON
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // '
            .replacingOccurrences(of: "…", with: "...")
        print("✅ Replaced smart quotes and ellipsis")
        
        // SHOW THE ENTIRE JSON
        print("\n📋 COMPLETE CLEANED JSON:")
        print(String(repeating: "=", count: 80))
        print(cleanJSON)
        print(String(repeating: "=", count: 80))
        print("Total length: \(cleanJSON.count) characters\n")
        
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            print("❌ Could not convert to UTF-8 data")
            throw PromptEngineError.invalidJSON("Could not convert response to UTF-8 data")
        }
        
        print("✅ Converted to Data: \(jsonData.count) bytes")
        
        // TRY TO PARSE AS GENERIC JSON FIRST TO SEE STRUCTURE
        print("\n🔍 ATTEMPTING GENERIC JSON PARSE TO SEE STRUCTURE...")
        if let genericJSON = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            print("✅ Valid JSON structure detected")
            print("Root keys: \(genericJSON.keys.sorted().joined(separator: ", "))")
            
            if let beats = genericJSON["beats"] as? [[String: Any]] {
                print("Beats array count: \(beats.count)")
                for (index, beat) in beats.enumerated() {
                    print("\nBeat \(index + 1) keys: \(beat.keys.sorted().joined(separator: ", "))")
                }
            }
        } else {
            print("❌ NOT VALID JSON - Can't even parse as generic object")
            print("\n🔍 FINDING JSON ERROR POSITION...")
            
            // Try to find where it breaks
            for i in stride(from: cleanJSON.count, through: 100, by: -100) {
                let substring = String(cleanJSON.prefix(i))
                if let data = substring.data(using: .utf8),
                   let _ = try? JSONSerialization.jsonObject(with: data) {
                    print("✅ JSON is valid up to character \(i)")
                    print("Problem likely after character \(i)")
                    if i + 100 < cleanJSON.count {
                        let startIndex = cleanJSON.index(cleanJSON.startIndex, offsetBy: i)
                        let endIndex = cleanJSON.index(cleanJSON.startIndex, offsetBy: min(i + 100, cleanJSON.count))
                        print("Problem area: \(cleanJSON[startIndex..<endIndex])")
                    }
                    break
                }
            }
            
            throw PromptEngineError.invalidJSON("JSON syntax error - see debug output above")
        }
        
        print("\n🔬 ATTEMPTING TO DECODE TO BeatResponse...")
        
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(BeatResponse.self, from: jsonData)
            
            print("✅ BEAT JSON DECODED SUCCESSFULLY!")
            print("Section ID: \(response.sectionId)")
          //  print("Section Role: \(response.sectionRole)")
            print("Beats found: \(response.beats.count)")
            
            return response
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("\n❌ BEAT KEY NOT FOUND ERROR")
            print("Missing key: '\(key.stringValue)'")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            throw PromptEngineError.invalidJSON("Missing key: \(key.stringValue)")
            
        } catch let DecodingError.typeMismatch(type, context) {
            print("\n❌ BEAT TYPE MISMATCH ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            throw PromptEngineError.invalidJSON("Type mismatch - expected \(type)")
            
        } catch let DecodingError.dataCorrupted(context) {
            print("\n❌ BEAT DATA CORRUPTED ERROR")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            
            throw PromptEngineError.invalidJSON("Data corrupted")
            
        } catch {
            print("\n❌ UNKNOWN BEAT DECODING ERROR")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
            
            throw PromptEngineError.parsingFailed("Decoder error: \(error.localizedDescription)")
        }
    }
    
    func parseResponse1(_ jsonString: String) throws -> BeatResponse {
        print("\n")
        print("========================================")
        print("🎯 PARSING BEAT BOUNDARIES (A1b)")
        print("========================================")
        
        print("\n📥 RAW JSON RESPONSE:")
        print("Length: \(jsonString.count) characters")
        print("First 200 chars: \(String(jsonString))")
        if jsonString.count > 200 {
            print("Last 200 chars: \(String(jsonString.suffix(200)))")
        }
        
        // Clean JSON
        var cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("\n🧹 CLEANING JSON...")
        
        if cleanJSON.hasPrefix("```json") {
            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ Removed markdown fences")
        }
        
        print("\n📋 CLEANED JSON:")
        print("Length after cleaning: \(cleanJSON.count) characters")
        print("First 500 chars:")
        print(String(cleanJSON.prefix(500)))
        
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            print("❌ Could not convert to UTF-8 data")
            throw PromptEngineError.invalidJSON("Could not convert to UTF-8 data")
        }
        
        print("✅ Converted to Data: \(jsonData.count) bytes")
        
        print("\n🔬 ATTEMPTING TO DECODE JSON...")
        
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(BeatResponse.self, from: jsonData)
            print("✅ JSON DECODED SUCCESSFULLY!")
            print("Section ID: \(response.sectionId)")
            print("Beats found: \(response.beats.count)")
            
            // Log each beat
            for (index, beat) in response.beats.enumerated() {
                print("\nBeat \(index + 1):")
                print("  ID: \(beat.beatId)")
                print("  Type: \(beat.type)")
                print("  Word range: \(beat.startWordIndex) - \(beat.endWordIndex)")
                print("  Text preview: '\(String(beat.text.prefix(60)))'...")
            }
            
            print("\n========================================")
            print("✅ BEAT PARSING COMPLETE")
            print("========================================\n")
            
            return response
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("\n❌ KEY NOT FOUND ERROR")
            print("Missing key: '\(key.stringValue)'")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            throw PromptEngineError.invalidJSON("Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.typeMismatch(type, context) {
            print("\n❌ TYPE MISMATCH ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            throw PromptEngineError.invalidJSON("Type mismatch - expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.valueNotFound(type, context) {
            print("\n❌ VALUE NOT FOUND ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            throw PromptEngineError.invalidJSON("Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch let DecodingError.dataCorrupted(context) {
            print("\n❌ DATA CORRUPTED ERROR")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            throw PromptEngineError.invalidJSON("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            
        } catch {
            print("\n❌ UNKNOWN DECODING ERROR")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
            throw PromptEngineError.invalidJSON("Unknown error: \(error.localizedDescription)")
        }
    }
    
    func calculateTimestamps(response: BeatResponse) throws -> SimpleBeatData {
        print("\n")
        print("========================================")
        print("⏱️ CALCULATING BEAT TIMESTAMPS (A1b)")
        print("========================================")
        
        guard let transcript = video.transcript else {
            throw PromptEngineError.noTranscript
        }
        
        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)
        
        print("\n📊 Timestamp Calculator Stats:")
        print("Total words: \(transcript.split(separator: " ").count)")
        print("Words per second: \(calculator.wordsPerSecond)")
        
        var beatsWithTimestamps: [SimpleBeat] = []
        
        print("\n🔍 Processing Beats:")
        for (index, beatItem) in response.beats.enumerated() {
             let startTime = calculator.calculateTimestampFromWordIndex(beatItem.startWordIndex)
             let endTime = calculator.calculateTimestampFromWordIndex(beatItem.endWordIndex)
             
             let beat = SimpleBeat(
                 beatId: beatItem.beatId,
                 type: beatItem.type,
                 timeRange: TimeRange(start: startTime, end: endTime),
                 text: beatItem.text,
                 startWordIndex: beatItem.startWordIndex,
                 endWordIndex: beatItem.endWordIndex,
                 stance: beatItem.stance,
                 tempo: beatItem.tempo,
                 formality: beatItem.formality,
                 questionCount: beatItem.questionCount,
                 containsAnchor: beatItem.containsAnchor,
                 anchorText: beatItem.anchorText,
                 anchorFunction: beatItem.anchorFunction,
                 proofMode: beatItem.proofMode
             )
             
             beatsWithTimestamps.append(beat)
         }
        
        print("\n✅ All beat timestamps calculated")
        
        // Create BeatData
        let beatData = SimpleBeatData(
            sectionId: response.sectionId,
            beats: beatsWithTimestamps
        )
        
        print("\n========================================")
        print("✅ BEAT TIMESTAMP CALCULATION COMPLETE")
        print("========================================\n")
        
        return beatData
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Response Structures (SIMPLIFIED)
    
    struct BeatResponse: Codable {
        let sectionId: String
        let beats: [BeatItem]
        
        struct BeatItem: Codable {
            let beatId: String
            let type: String
            let text: String
            let startWordIndex: Int
            let endWordIndex: Int
            // Essential fields for A3 clustering
            let stance: String
            let tempo: String
            let formality: Int
            let questionCount: Int
            let containsAnchor: Bool
            let anchorText: String
            let anchorFunction: String
            let proofMode: String
        }
    }
}
*/
// MARK: - A1b Context

struct A1bContext {
    let videoId: String
    let transcript: String
    let totalSections: Int
    let allRoles: [String]
    let currentSectionIndex: Int
    let roleInstanceNumber: Int
    let totalRoleInstances: Int
    let priorSectionRole: String?
    let nextSectionRole: String?
    let sectionDurationSeconds: Int
    let expectedBeatRange: String
}

// MARK: - Helper Functions

func computeExpectedBeatRangeFromDuration(durationSeconds: Int) -> String {
    // Estimate based on typical speech (~2.5 words/second, ~150 words/minute)
    // Short section (<30s) = 2-3 beats
    // Medium section (30-60s) = 3-5 beats
    // Long section (60-120s) = 4-6 beats
    // Very long section (>120s) = 5-8 beats
    switch durationSeconds {
    case 0..<30:    return "2-3"
    case 30..<60:   return "3-5"
    case 60..<120:  return "4-6"
    case 120..<180: return "5-7"
    default:        return "6-8"
    }
}

func buildA1bContext(
    video: YouTubeVideo,
    sections: [SectionData],
    currentIndex: Int
) -> A1bContext {
    let currentSection = sections[currentIndex]
    let allRoles = sections.map { $0.role.uppercased() }
    let currentRole = currentSection.role.uppercased()

    let roleInstances = sections.enumerated().filter { $0.element.role.uppercased() == currentRole }
    let instanceNumber = roleInstances.firstIndex(where: { $0.offset == currentIndex })! + 1
    let totalInstances = roleInstances.count

    let priorRole = currentIndex > 0 ? sections[currentIndex - 1].role.uppercased() : nil
    let nextRole = currentIndex < sections.count - 1 ? sections[currentIndex + 1].role.uppercased() : nil

    // Calculate duration from word indexes (preferred) or time range (legacy)
    let videoDurationSeconds = TimestampCalculator.parseDuration(video.duration)
    let durationSeconds: Int
    if let startWord = currentSection.startWordIndex,
       let endWord = currentSection.endWordIndex,
       let transcript = video.transcript,
       videoDurationSeconds > 0 {
        let totalWords = transcript.split(separator: " ").count
        let wordsPerSecond = Double(totalWords) / Double(videoDurationSeconds)
        let wordCount = endWord - startWord + 1
        durationSeconds = max(1, Int(Double(wordCount) / wordsPerSecond))
    } else if let timeRange = currentSection.timeRange {
        durationSeconds = timeRange.end - timeRange.start
    } else if videoDurationSeconds > 0 {
        // Fallback: estimate based on video duration / section count
        durationSeconds = max(1, videoDurationSeconds / sections.count)
    } else {
        // Ultimate fallback
        durationSeconds = 60
    }

    return A1bContext(
        videoId: video.videoId,
        transcript: video.transcript ?? "",
        totalSections: sections.count,
        allRoles: allRoles,
        currentSectionIndex: currentIndex,
        roleInstanceNumber: instanceNumber,
        totalRoleInstances: totalInstances,
        priorSectionRole: priorRole,
        nextSectionRole: nextRole,
        sectionDurationSeconds: durationSeconds,
        expectedBeatRange: computeExpectedBeatRangeFromDuration(durationSeconds: durationSeconds)
    )
}

// MARK: - Response Structures

struct BeatResponse: Codable {
    let sectionId: String
    let sectionRole: String
    let beatCount: Int
    let beats: [BeatItem]

    struct BeatItem: Codable {
        let beatId: String
        let type: String
        let text: String
        let boundarySentence: Int?  // Sentence number where beat ends (null for final beat)
        let stance: String
        let tempo: String
        let formality: Int
        let questionCount: Int
        let containsAnchor: Bool
        let anchorText: String
        let anchorFunction: String
        let proofMode: String
        let moveKey: String
        let sectionId: String
    }
}

// Note: SimpleBeat and SimpleBeatData are defined in Beat.swift

// MARK: - Validation

func validateBeatResponse(_ response: BeatResponse) -> [String] {
    var errors: [String] = []

    // Check beatCount matches
    if response.beatCount != response.beats.count {
        errors.append("beatCount (\(response.beatCount)) doesn't match beats array (\(response.beats.count))")
    }

    // Check moveKey validity
    for beat in response.beats {
        if beat.moveKey == "UNKNOWN" || beat.moveKey.isEmpty {
            errors.append("Beat \(beat.beatId) has invalid moveKey: '\(beat.moveKey)'")
        }
    }

    // Check boundarySentence validity (all except last should have boundary)
    for (index, beat) in response.beats.enumerated() {
        let isLastBeat = index == response.beats.count - 1
        if !isLastBeat && beat.boundarySentence == nil {
            errors.append("Beat \(beat.beatId) is missing boundarySentence (required for non-final beats)")
        }
    }

    // Note: Word index overlap validation happens after BoundaryResolver
    // since we no longer have word indexes in the response

    return errors
}

// MARK: - Cross-Section Validation

/// Validates that beats from all sections don't overlap with each other.
/// Call this after all A1b extractions complete to catch cross-section overlaps.
func validateGlobalBeatBoundaries(allBeats: [SimpleBeat]) -> [String] {
    var errors: [String] = []

    // Sort all beats by startWordIndex
    let sortedBeats = allBeats.sorted { $0.startWordIndex < $1.startWordIndex }

    // Check for overlaps between consecutive beats
    for i in 0..<(sortedBeats.count - 1) {
        let current = sortedBeats[i]
        let next = sortedBeats[i + 1]

        if current.endWordIndex >= next.startWordIndex {
            errors.append("Cross-section overlap: Beat '\(current.beatId)' (words \(current.startWordIndex)-\(current.endWordIndex)) overlaps with '\(next.beatId)' (words \(next.startWordIndex)-\(next.endWordIndex))")
        }
    }

    return errors
}

/// Validates that section word boundaries cover the entire transcript without gaps or overlaps.
func validateSectionBoundaries(sections: [SectionData], totalWords: Int) -> [String] {
    var errors: [String] = []

    // Filter to sections with word boundaries
    let sectionsWithBoundaries = sections.filter { $0.hasWordBoundaries }

    guard !sectionsWithBoundaries.isEmpty else {
        errors.append("No sections have word boundaries - cannot validate")
        return errors
    }

    // Sort by start word index
    let sorted = sectionsWithBoundaries.sorted { ($0.startWordIndex ?? 0) < ($1.startWordIndex ?? 0) }

    // Check first section starts at 0
    if let first = sorted.first, first.startWordIndex != 0 {
        errors.append("First section doesn't start at word 0 (starts at \(first.startWordIndex ?? -1))")
    }

    // Check last section ends at totalWords - 1
    if let last = sorted.last, last.endWordIndex != totalWords - 1 {
        errors.append("Last section doesn't end at word \(totalWords - 1) (ends at \(last.endWordIndex ?? -1))")
    }

    // Check for gaps and overlaps between sections
    for i in 0..<(sorted.count - 1) {
        let current = sorted[i]
        let next = sorted[i + 1]

        guard let currentEnd = current.endWordIndex, let nextStart = next.startWordIndex else {
            continue
        }

        if currentEnd + 1 != nextStart {
            if currentEnd >= nextStart {
                errors.append("Section overlap: '\(current.id)' ends at \(currentEnd), '\(next.id)' starts at \(nextStart)")
            } else {
                errors.append("Section gap: '\(current.id)' ends at \(currentEnd), '\(next.id)' starts at \(nextStart) (missing words \(currentEnd + 1) to \(nextStart - 1))")
            }
        }
    }

    return errors
}

// MARK: - Beat Prompt Engine

struct BeatPromptEngine {
    let video: YouTubeVideo
    let sections: [SectionData]
    let currentIndex: Int
    let section: SectionData
    let context: A1bContext

    init(video: YouTubeVideo, sections: [SectionData], currentIndex: Int) {
        self.video = video
        self.sections = sections
        self.currentIndex = currentIndex
        self.section = sections[currentIndex]
        self.context = buildA1bContext(video: video, sections: sections, currentIndex: currentIndex)
    }

    func generatePrompt() -> String {
        guard let transcript = video.transcript else {
            return "⚠️ No transcript available"
        }

        // Parse FULL transcript into sentences FIRST (same parsing as A1a)
        let allSentences = SentenceParser.parse(transcript)

        // Extract this section's sentences by sentence index (from A1a)
        let sentences: [String]
        let sentenceCount: Int

        if let startSentence = section.startSentenceIndex,
           let endSentence = section.endSentenceIndex,
           startSentence >= 0 && endSentence < allSentences.count && startSentence <= endSentence {
            // Extract sentences by index - NO re-parsing, same sentences as A1a
            sentences = Array(allSentences[startSentence...endSentence])
            sentenceCount = sentences.count
            print("📐 A1b generatePrompt: Extracting sentences [\(startSentence + 1)] to [\(endSentence + 1)] for \(section.role)")
            print("🔎 DEBUG generatePrompt: Section sentences being sent to LLM:")
            for (i, sent) in sentences.enumerated() {
                let preview = sent.count > 70 ? String(sent.prefix(70)) + "..." : sent
                print("  [\(i + 1)] \(preview)")
            }
        } else {
            // Fallback: no sentence boundaries available (legacy data)
            // Fall back to word-based extraction + re-parsing (may have boundary issues)
            print("⚠️ A1b: No sentence boundaries for \(section.role), falling back to word extraction")
            if let startWord = section.startWordIndex,
               let endWord = section.endWordIndex {
                let words = transcript.split(separator: " ").map(String.init)
                let sectionWords = Array(words[startWord...min(endWord, words.count - 1)])
                let sectionTranscript = sectionWords.joined(separator: " ")
                sentences = SentenceParser.parse(sectionTranscript)
                sentenceCount = sentences.count
            } else {
                sentences = allSentences
                sentenceCount = sentences.count
            }
        }

        // Format with numbers: [1] First sentence. [2] Second sentence.
        let numberedTranscript = sentences.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: " ")

        let beatIdPrefix = "\(video.videoId)_sect_\(context.currentSectionIndex + 1)_\(section.role.lowercased())"

        return """
════════════════════════════════════════
🚨 OUTPUT FORMAT: JSON ONLY 🚨
════════════════════════════════════════

Your response MUST be ONLY valid JSON.

❌ DO NOT include:
- Any text before the JSON (no "I'll analyze...", no "Here's the analysis:")
- Any text after the JSON (no summaries, no explanations)
- Any markdown formatting (no ```json blocks)

✅ Your response should start with { and end with }

════════════════════════════════════════
🛑 CRITICAL: READ THIS FIRST 🛑
════════════════════════════════════════

EVERY BEAT MUST END AT A SENTENCE BOUNDARY.

The transcript below is pre-split into numbered sentences: [1], [2], [3], etc.
Total sentences in this section: \(sentenceCount)

For each beat, provide the SENTENCE NUMBER where that beat ENDS.
This is simple: just tell us which [N] sentence is the last one in each beat.

EXAMPLE:
If beat 1 contains sentences [1] through [5], you output:
"boundarySentence": 5

RULES:
- boundarySentence = the sentence number of the LAST sentence in that beat
- Beats are contiguous: if beat 1 ends at [5], beat 2 starts at [6]
- The LAST beat doesn't need boundarySentence (it goes to end of section)
- Use the bracketed numbers [1], [2], etc.

════════════════════════════════════════

## ROLE

You are performing A1b: Beat Extraction.

Your job is to extract EXECUTABLE RHETORICAL ATOMS from a transcript section.

You do NOT summarize.
You do NOT explain.
You do NOT interpret.

You extract EXACT transcript text into COMPLETE, ATOMIC beats that each perform ONE rhetorical function.

────────────────────────────────────────
BOUNDARY IDENTIFICATION (CRITICAL)
────────────────────────────────────────

The section transcript is pre-split into numbered sentences: [1], [2], [3], etc.
Total sentences: \(sentenceCount)

For each beat, provide the SENTENCE NUMBER where that beat ENDS.
Code will use this to calculate exact boundaries deterministically.

EXAMPLE:
If the first beat ends at sentence [5], you output:
"boundarySentence": 5

RULES:
- boundarySentence = the sentence number of the LAST sentence in that beat
- Beats are contiguous: if beat 1 ends at [5], beat 2 starts at [6]
- The LAST beat doesn't need boundarySentence (it goes to end of section)
- Use the bracketed numbers [1], [2], etc. — NOT word counts

────────────────────────────────────────
SECTION CONTEXT (AUTHORITATIVE)
────────────────────────────────────────

Video ID: \(video.videoId)
Section ID: \(section.id)
Section: \(context.currentSectionIndex + 1) of \(context.totalSections)
Role: \(section.role.uppercased()) (instance \(context.roleInstanceNumber) of \(context.totalRoleInstances))
Video Structure: \(context.allRoles.joined(separator: " → "))
Prior Section: \(context.priorSectionRole ?? "none")
Next Section: \(context.nextSectionRole ?? "none")

- Section sentences: \(sentenceCount)
- Estimated duration: \(context.sectionDurationSeconds) seconds
- Expected beats: \(context.expectedBeatRange)

This context is TRUTH. Do not infer or override it.
Extract beats ONLY from this section.

────────────────────────────────────────
SECTION TRANSCRIPT (SENTENCES NUMBERED)
────────────────────────────────────────

\(numberedTranscript)

\(splitSentencePrompt())

────────────────────────────────────────
BEAT ATOMICITY RULES (SECONDARY — ONLY AFTER COMPLETENESS)
────────────────────────────────────────

ONLY AFTER ensuring completeness, then consider:
- 1 beat = 1 rhetorical function
- Split when stance/tempo/function changes
- BUT ONLY if the split creates TWO complete beats

If splitting would create a fragment → KEEP MERGED.

────────────────────────────────────────
SIZE GUIDANCE (APPROXIMATE — DO NOT COUNT)
────────────────────────────────────────

- Typical beats feel like a short paragraph (2-5 sentences)
- Large beats (100+ words) are FINE if they're complete sentences
- Micro-beats (under 20 words) are SUSPICIOUS — verify they're complete sentences
- When in doubt, MERGE rather than create fragments

Do NOT count words. Prioritize completeness over size.

────────────────────────────────────────
SPAN EXCLUSIVITY (NON-NEGOTIABLE)
────────────────────────────────────────

Every sentence belongs to EXACTLY ONE beat.

- Beats CANNOT overlap
- Beats CANNOT duplicate text
- If beat N ends at sentence [5], beat N+1 starts at sentence [6]
- Sentences must be exclusive and contiguous
- Text must be VERBATIM (no paraphrasing, no restating)

If text already appeared elsewhere → use TRANSITION or CALLBACK, NOT duplication.

────────────────────────────────────────
BEAT TYPE TAXONOMY (15 TYPES)
────────────────────────────────────────

PRIMARY (rhetorical function):

TEASE       - Create curiosity WITHOUT revealing
              "Here's what nobody tells you..."
              Must NOT contain the payoff

QUESTION    - Rhetorical or direct question
              Must contain ? or clearly implied question

PROMISE     - Explicit commitment to deliver
              "I'm going to show you..." "You'll learn..."

DATA        - Statistics, facts, numbers, measurements
              Must contain a SPECIFIC factual claim

STORY       - Narrative with characters/timeline
              Has beginning/middle/end structure

AUTHORITY   - Expert quote, study citation, credentials
              "Scientists say..." "Research shows..."

SYNTHESIS   - Interpretation, "here's what this means"
              Explains significance, not just facts

TURN        - Major subversion that REFRAMES understanding
              RARE — usually ONE per video, in TURN section
              Must actually CHANGE the viewer's frame

CORRECTION  - Local "but actually..." undermining
              Does NOT reframe entire video
              Common in EVIDENCE sections

PRINCIPLE   - General rule, pattern, or framework
              "The key is..." "This is why..."

STRUCTURAL (connective function):

TRANSITION  - Bridge between ideas/sections
              "So now that we understand X..."

CALLBACK    - Reference to earlier point
              "Remember when I said..."

REFRAME     - Shift perspective on established point
              "Think about it differently..."

PREVIEW     - Signal what's coming next
              "We'll see why shortly..."

VISUAL (video-specific):

CLIP_REACTION - Narrate/react to visual footage
                "Watch this..." "Look at what happens..."

────────────────────────────────────────
BEAT TYPE CONTRACT RULE
────────────────────────────────────────

Some beat types are "soft buckets" that accumulate junk:
- SYNTHESIS
- PRINCIPLE
- TRANSITION
- REFRAME

If a beat could plausibly be labeled as one of these,
you MUST verify it is NOT actually:
- DATA (has specific facts?)
- STORY (has narrative structure?)
- CORRECTION (undermines prior claim?)

These four types are valid, but they are NOT catch-alls.
Use them only when nothing else fits AND the text genuinely performs that function.

────────────────────────────────────────
SECTION-SPECIFIC GUIDANCE
────────────────────────────────────────

\(getSectionRoleGuidance())

────────────────────────────────────────
TURN BEAT RULES (HARD)
────────────────────────────────────────

If this is a TURN section:
- EXACTLY ONE beat with type = TURN (0 = FAIL, >1 = FAIL)
- Other beats: TRANSITION, CALLBACK, SYNTHESIS, DATA, STORY
- Beat count: 2-4 typical (TIGHT)

If this is NOT a TURN section:
- TURN beats are RARE but allowed if genuine reframe
- Most "but actually..." = CORRECTION, not TURN
- Test: "Does this change the ENTIRE video's frame?" If no → CORRECTION

────────────────────────────────────────
BEAT PURPOSE CHECK (MANDATORY)
────────────────────────────────────────

Before emitting EACH beat, verify:

- TEASE: Does it withhold the answer? (Reveals → WRONG)
- DATA: Does it contain a specific fact? (Vague → WRONG)
- TURN: Does it reframe understanding? (Local correction → use CORRECTION)
- QUESTION: Does it actually ask? (Statement → WRONG)
- STORY: Does it have narrative structure? (Description → may be DATA)

If text doesn't match label → RELABEL or SPLIT.

────────────────────────────────────────
EXECUTABILITY TEST (MANDATORY)
────────────────────────────────────────

Before emitting EACH beat, ask:

1. Can this beat be replayed mechanically in sequence?
2. Does it perform an ACTION (tease, prove, reframe), not commentary?
3. Does it require interpretation to understand?
4. Could it stand alone without explanation?

If ANY answer is wrong → SPLIT or RELABEL.

A beat is executable if a compiler could use it as an instruction.
A beat is NOT executable if it requires human judgment to understand.

────────────────────────────────────────
moveKey (REQUIRED — NO EXCEPTIONS)
────────────────────────────────────────

moveKey = {SECTION_ROLE}_{BEAT_TYPE}_{STANCE}_{TEMPO}

Example: EVIDENCE_DATA_NEUTRAL_STEADY

Rules:
- "UNKNOWN" is ILLEGAL
- Every beat MUST have a valid moveKey

────────────────────────────────────────
REQUIRED FIELDS (15 per beat)
────────────────────────────────────────

beatId:           "\(beatIdPrefix)_b1", "_b2", etc.
type:             One of 15 beat types
text:             EXACT transcript text (verbatim, no paraphrasing)
boundarySentence: Sentence number where this beat ends (null for final beat)
stance:           "critical" | "neutral" | "playful" | "helpful"
tempo:            "fast" | "steady" | "slow_build"
formality:        1-10 scale
questionCount:    Integer (0 if none)
containsAnchor:   Boolean
anchorText:       String (empty if no anchor)
anchorFunction:   "opener" | "turn" | "proofFrame" | "none"
proofMode:        "none" | "stat" | "anecdote" | "authority" | "demo" | "logic"
moveKey:          {ROLE}_{TYPE}_{STANCE}_{TEMPO}
sectionId:        "\(video.videoId)_\(section.id)"

────────────────────────────────────────
OUTPUT FORMAT (STRICT JSON)
────────────────────────────────────────

{
  "sectionId": "\(video.videoId)_\(section.id)",
  "sectionRole": "\(section.role.uppercased())",
  "beatCount": <integer>,
  "beats": [
    {
      "beatId": "\(beatIdPrefix)_b1",
      "type": "DATA",
      "text": "Exact transcript text here. The thermal data shows a clear pattern.",
      "boundarySentence": 5,
      "stance": "neutral",
      "tempo": "steady",
      "formality": 6,
      "questionCount": 0,
      "containsAnchor": false,
      "anchorText": "",
      "anchorFunction": "none",
      "proofMode": "stat",
      "moveKey": "EVIDENCE_DATA_NEUTRAL_STEADY",
      "sectionId": "\(video.videoId)_\(section.id)"
    },
    {
      "beatId": "\(beatIdPrefix)_b2",
      "type": "SYNTHESIS",
      "text": "And that's why we need to rethink everything.",
      "boundarySentence": null,
      "stance": "helpful",
      "tempo": "steady",
      "formality": 5,
      "questionCount": 0,
      "containsAnchor": false,
      "anchorText": "",
      "anchorFunction": "none",
      "proofMode": "logic",
      "moveKey": "EVIDENCE_SYNTHESIS_HELPFUL_STEADY",
      "sectionId": "\(video.videoId)_\(section.id)"
    }
  ]
}

────────────────────────────────────────
VALIDATION CHECKLIST (before output)
────────────────────────────────────────

=== COMPLETENESS GATE (CHECK FIRST — FAILURES INVALIDATE OUTPUT) ===

☐ Every beat ends with sentence-ending punctuation (. ! ? or closing quote ")
☐ No beat ends with: and, but, so, because, the, a, of, to, that, which, is, are, was, were, we, they, I, you, it, in, on, at
☐ Every beat contains at least one complete sentence
☐ No beat is under 10 words unless it's a complete sentence (e.g., "That's wild!")

If ANY of these fail → GO BACK and merge the fragment with its neighbor.

=== ONLY IF COMPLETENESS PASSES, CHECK THESE ===

☐ Beat count within expected range (\(context.expectedBeatRange))
☐ Each beat (except the last) has boundarySentence with a valid number (1 to \(sentenceCount))
☐ Last beat has boundarySentence: null
☐ boundarySentence values are in ascending order
☐ Beats are in sequential order
☐ Every beat has all 15 fields
☐ Every moveKey is valid (not UNKNOWN)
☐ Text is EXACT from transcript
☐ If TURN section: exactly ONE TURN beat
☐ Each beat performs ONE rhetorical function
☐ First beat type matches section role guidance
☐ Each beat passes executability test

────────────────────────────────────────
RED FLAGS (reconsider if seen)
────────────────────────────────────────

⚠️ Beat count matches other sections exactly — likely pattern-matching
⚠️ EVIDENCE section opens with TEASE — usually wrong
⚠️ TURN section has ≠1 TURN beat — extraction failed
⚠️ Beat has 4+ sentences — verify single function
⚠️ Beat contains multiple rhetorical functions — should split
⚠️ Beat text doesn't fulfill declared function — relabel
⚠️ moveKey missing or UNKNOWN — ILLEGAL
⚠️ boundarySentence outside valid range (1 to \(sentenceCount)) — INVALID
⚠️ DATA beat without factual claim — wrong label
⚠️ TEASE reveals answer — wrong label
⚠️ SYNTHESIS/PRINCIPLE/TRANSITION used as catch-all — verify specificity
⚠️ Beat ends with connector word (and, but, so, etc.) — FRAGMENT, invalid
⚠️ Beat has no sentence-ending punctuation — INCOMPLETE, invalid
⚠️ Beat is a single short clause — likely FRAGMENT, merge with neighbor

────────────────────────────────────────
FINAL REMINDER
────────────────────────────────────────

You are extracting RHETORICAL EXECUTION UNITS.

If the output cannot be:
- Replayed mechanically
- Validated deterministically
- Reused without interpretation

...it is WRONG.

Return ONLY valid JSON. No markdown. No commentary.
"""
    }

    /// Detects candidate beat boundaries from linguistic signals in the transcript
    private func detectBeatBoundaries(sentences: [String]) -> [Int] {
        var candidates: [Int] = []

        // Transition phrase patterns that signal beat boundaries
        let transitionStarters = [
            "now to", "and now", "let's", "so now", "moving on",
            "next up", "speaking of", "turning to", "but first",
            "before we", "after that", "finally", "first", "second", "third"
        ]

        // Definition closure patterns that end a thought
        let closurePatterns = [
            "that is", "that's what", "that's how", "that's why",
            "this is what", "this is how", "this is why",
            "in other words", "to put it simply", "basically"
        ]

        for (index, sentence) in sentences.enumerated() {
            let lowercased = sentence.lowercased()

            // Check if this sentence STARTS with a transition (marks beat boundary BEFORE it)
            let hasTransitionStart = transitionStarters.contains { lowercased.hasPrefix($0) }

            // Check if this sentence contains a closure pattern (marks beat boundary AT it)
            let hasClosure = closurePatterns.contains { lowercased.contains($0) }

            // Check for explicit pivot markers
            let hasPivot = lowercased.contains("but here's") ||
                          lowercased.contains("here's the thing") ||
                          lowercased.contains("the real") ||
                          lowercased.contains("actually")

            if hasTransitionStart || hasClosure || hasPivot {
                // Transition starters mark the boundary at the PREVIOUS sentence
                // Closures mark the boundary at THIS sentence
                let boundaryIndex = hasTransitionStart ? index : index + 1
                if boundaryIndex > 0 && boundaryIndex <= sentences.count && !candidates.contains(boundaryIndex) {
                    candidates.append(boundaryIndex)
                }
            }
        }

        // Always include the section end as a valid boundary
        if !candidates.contains(sentences.count) {
            candidates.append(sentences.count)
        }

        return candidates.sorted()
    }

    private func splitSentencePrompt() -> String {
        // Parse section sentences for boundary detection
        guard let transcript = video.transcript else { return "" }
        let allSentences = SentenceParser.parse(transcript)

        let sentences: [String]
        if let startSentence = section.startSentenceIndex,
           let endSentence = section.endSentenceIndex,
           startSentence >= 0 && endSentence < allSentences.count && startSentence <= endSentence {
            sentences = Array(allSentences[startSentence...endSentence])
        } else {
            sentences = allSentences
        }

        let detectedBoundaries = detectBeatBoundaries(sentences: sentences)
        let boundaryList = detectedBoundaries.map { "[\($0)]" }.joined(separator: ", ")
        let boundaryCount = detectedBoundaries.count

        return """
────────────────────────────────────────
BEAT BOUNDARY SYSTEM (READ FIRST)
────────────────────────────────────────

WHY THIS EXISTS:

You are extracting beats so they can be REWRITTEN to match this creator's style.
For rewriting to work, beats must be:
- Stable (same boundaries every time)
- Large enough to contain complete rhetorical moves
- Deterministic (no interpretation drift)

To achieve this, beat boundaries have been PRE-COMPUTED from linguistic signals.
You do not discover boundaries. You SELECT from a fixed set.

This is intentional. Discovery creates variance. Selection creates stability.

────────────────────────────────────────
ALLOWED BEAT BOUNDARIES (NON-NEGOTIABLE)
────────────────────────────────────────

You MAY ONLY end beats at the following sentence numbers:

\(boundaryList)

These \(boundaryCount) boundaries were detected from:
- Explicit transition phrases ("Now to...", "And now...", "Let's...")
- Definition closures ("That is...", "That's what...")
- Pivot markers ("But here's the thing...", "The real...")
- Section end

You CANNOT end a beat at any sentence not in this list.
This constraint is absolute. No exceptions.

────────────────────────────────────────
YOUR TASK
────────────────────────────────────────

1. REVIEW the allowed boundaries above
2. DECIDE which boundaries to USE (you don't need all of them)
3. GROUP sentences between used boundaries into beats
4. ASSIGN one dominant rhetorical function to each beat
5. OUTPUT the beats with their types and text

You are making SELECTION decisions, not DISCOVERY decisions.

────────────────────────────────────────
WHEN TO USE A BOUNDARY
────────────────────────────────────────

Use a boundary when the rhetorical function CHANGES at that point:

- DATA section ends, SYNTHESIS begins → use boundary
- AUTHORITY quote ends, narrator STORY begins → use boundary
- Explanation ends, new topic TRANSITION begins → use boundary

The function change must be CLEAR, not subtle.

────────────────────────────────────────
WHEN TO SKIP A BOUNDARY
────────────────────────────────────────

Skip a boundary when:

1. QUESTIONS FOLLOW A CLOSURE
   A closure like "That's what you see" followed by rhetorical questions
   is NOT a real boundary. The questions continue the thought.

   Example:
   [15] That's what you see as an image.
   [16] But what happens next?
   [17] How does this change things?

   → Skip [15]. Keep [15-17] in the same beat.

2. FUNCTION STAYS THE SAME
   If sentences on both sides of a boundary have the same function
   (DATA → DATA, STORY → STORY), skip the boundary.

   Example:
   [22] One of the smallest black holes is J1650.
   [23] Its diameter is only about as long as Manhattan.
   [24] One step up would be the black hole in Messier 15.

   → Even if [23] is an allowed boundary, skip it. All three are DATA.

3. SPLITTING WOULD CREATE A FRAGMENT
   If using a boundary would create a beat with only 1-2 sentences
   that can't stand alone as a complete rhetorical move, skip it.

────────────────────────────────────────
HOMOGENEOUS FUNCTION SPANS
────────────────────────────────────────

Some sections contain long spans where the function does NOT change:

DATA → DATA → DATA → DATA → DATA (comparison sequence)
STORY → STORY → STORY → STORY (narrative arc)
AUTHORITY → AUTHORITY → AUTHORITY (extended quote)

In these cases:

- KEEP THEM TOGETHER as one beat
- Large beats (10+ sentences) are EXPECTED, not wrong
- Do NOT split for size, pacing, or "paragraph feel"
- The goal is STABLE EXECUTION BLOCKS, not perfect atoms

Example: A 15-sentence comparison of black hole sizes should be ONE beat
if it's all serving the same DATA function.

────────────────────────────────────────
QUESTIONS ARE NOT BOUNDARIES
────────────────────────────────────────

Questions do NOT create or justify boundaries:

- Rhetorical questions ("But what does this mean?")
- Forward-opening questions ("What happens next?")
- Teaser questions ("Can you guess?")

These remain INSIDE the surrounding beat.

Even if a question sentence appears in the allowed boundaries list,
do NOT use it as a split point. Questions continue thought, they don't break it.

────────────────────────────────────────
DOMINANT FUNCTION RULE
────────────────────────────────────────

If a span between two boundaries contains MIXED signals:

- A DATA point followed by a brief SYNTHESIS comment
- A STORY beat with one AUTHORITY quote embedded
- A TRANSITION sentence followed by DATA

You CANNOT split further. Choose the DOMINANT function:

- What does MOST of the span do?
- What is the PRIMARY rhetorical move?
- Label the beat by that function.

Minor embedded moments are acceptable. Perfect atomicity is not the goal.

────────────────────────────────────────
STABILITY PRIORITY (GOVERNING PRINCIPLE)
────────────────────────────────────────

When in doubt about any decision:

- Use FEWER boundaries, not more
- Create LARGER beats, not smaller
- Preserve CONTEXT over granularity
- Choose STABILITY over precision

A beat that's "too big" but stable is better than
a beat that's "perfectly sized" but drifts between runs.

You are building a foundation for rewriting.
The foundation must not move.

────────────────────────────────────────
DECISION CHECKLIST (BEFORE OUTPUT)
────────────────────────────────────────

For each boundary you're considering using:

☐ Does the function CLEARLY change here?
☐ Is this NOT a closure followed by questions?
☐ Would both resulting beats be complete rhetorical moves?
☐ Would skipping this boundary create an unmanageably mixed beat?

If ANY answer is NO → skip the boundary.
"""
    }

    private func getSectionRoleGuidance() -> String {
        switch section.role.uppercased() {
        case "HOOK":
            return """
            HOOK sections:
            - First beat MUST be: TEASE, QUESTION, or STORY
            - If violated, justify OR relabel
            - May include: PROMISE, DATA (shocking stat), PREVIEW
            - Tempo: Usually fast
            - Beat count: 3-5 typical
            """
        case "SETUP":
            return """
            SETUP sections:
            - First beat MUST be: TRANSITION, STORY, or PRINCIPLE (NOT TEASE)
            - If violated, justify OR relabel
            - May include: DATA (context), AUTHORITY
            - Tempo: Usually steady
            - Beat count: 4-6 typical
            """
        case "EVIDENCE":
            return """
            EVIDENCE sections:
            - First beat MUST be: TRANSITION, DATA, or CLIP_REACTION (NOT TEASE)
            - If violated, justify OR relabel
            - May include: DATA, STORY, AUTHORITY, CORRECTION, CLIP_REACTION
            - CORRECTION beats common here ("but actually...")
            - Tempo: Usually steady or slow_build
            - Beat count: 4-7 typical
            - You are PROVING, not teasing
            """
        case "TURN":
            return """
            TURN sections:
            - MUST contain EXACTLY ONE beat with type = TURN (0 = FAIL, >1 = FAIL)
            - First beat MUST be: CALLBACK, REFRAME, or TRANSITION
            - If violated, justify OR relabel
            - Other beats: TRANSITION, CALLBACK, SYNTHESIS, DATA, STORY
            - Tempo: Often steady → fast at turn moment
            - Beat count: 2-4 typical (TIGHT)
            """
        case "PAYOFF":
            return """
            PAYOFF sections:
            - First beat MUST be: SYNTHESIS, PRINCIPLE, or CALLBACK
            - If violated, justify OR relabel
            - May include: DATA (results), PRINCIPLE, PREVIEW
            - Should deliver on HOOK's promise
            - Tempo: Usually steady
            - Beat count: 3-6 typical
            """
        case "CTA":
            return """
            CTA sections:
            - First beat MUST be: TRANSITION or CALLBACK
            - If violated, justify OR relabel
            - May include: PROMISE (future content)
            - Keep short
            - Beat count: 1-3 typical
            """
        case "SPONSORSHIP":
            return """
            SPONSORSHIP sections:
            - Usually 1-2 beats
            - Type: Often STORY or AUTHORITY
            - Clearly separate from main content
            """
        default:
            return """
            General guidance:
            - Match beat types to section function
            - Vary tempo across beats
            """
        }
    }
    
    private func formatTimeRange(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func getSectionBoundariesText() -> String {
        // Prefer word boundaries (new format)
        if section.hasWordBoundaries,
           let startWord = section.startWordIndex,
           let endWord = section.endWordIndex {
            return """
            Section Context:
            - This section spans words \(startWord) to \(endWord) in the full transcript
            - Extract beats ONLY from this section's text (shown above with numbered sentences)
            - First beat starts at sentence [1]
            - Last beat ends at the last sentence
            - Use boundarySentence to mark where each beat ends
            """
        }

        // Fall back to time range (legacy format)
        if let timeRange = section.timeRange {
            return """
            Section Time Range (legacy - word boundaries not available):
            - Time range: \(formatTimeRange(timeRange.start)) - \(formatTimeRange(timeRange.end))
            ⚠️ This video was analyzed before word boundaries were added.
            ⚠️ For accurate beat extraction, re-run A1a analysis first.
            """
        }

        // Neither available - should not happen
        return """
            ⚠️ WARNING: No section boundaries available.
            Extract beats based on section role and video structure.
            """
    }

    // MARK: - JSON Extraction Helper

    /// Extracts JSON from a response that may contain preamble text or markdown fences
    private func extractJSON(from response: String) -> String? {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace smart quotes and ellipsis first
        text = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // '
            .replacingOccurrences(of: "…", with: "...")

        // Try to find JSON in markdown code block first (most common case)
        if let jsonBlockRange = text.range(of: "```json") {
            let afterMarker = text[jsonBlockRange.upperBound...]
            if let endRange = afterMarker.range(of: "```") {
                let jsonContent = String(afterMarker[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Extracted JSON from ```json block")
                return jsonContent
            }
        }

        // Try generic code block
        if let codeBlockRange = text.range(of: "```") {
            let afterMarker = text[codeBlockRange.upperBound...]
            // Skip language identifier if present (e.g., "json\n")
            var jsonStart = afterMarker.startIndex
            if let newlineIndex = afterMarker.firstIndex(of: "\n") {
                jsonStart = afterMarker.index(after: newlineIndex)
            }
            if let endRange = afterMarker.range(of: "```", range: jsonStart..<afterMarker.endIndex) {
                let jsonContent = String(afterMarker[jsonStart..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ Extracted JSON from ``` block")
                return jsonContent
            }
        }

        // If no markdown block, try to find JSON object directly
        // Look for first { and match to last }
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            let jsonContent = String(text[firstBrace...lastBrace])
            // Validate it's actually JSON by checking basic structure
            if jsonContent.contains("\"") && jsonContent.count > 10 {
                print("✅ Extracted JSON object from position \(text.distance(from: text.startIndex, to: firstBrace))")
                return jsonContent
            }
        }

        // If already clean JSON, return as-is
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return text
        }

        return nil
    }

    // MARK: - Parsing

    func parseResponse(_ jsonString: String) throws -> BeatResponse {
        print("\n")
        print("========================================")
        print("🎵 STARTING BEAT JSON PARSING")
        print("========================================")
        print("Section: \(section.id) (\(section.role))")

        print("\n📥 RAW BEAT JSON RESPONSE:")
        print("Length: \(jsonString.count) characters")
        print("First 300 chars: \(String(jsonString.prefix(300)))")
        if jsonString.count > 300 {
            print("Last 200 chars: \(String(jsonString.suffix(200)))")
        }

        print("\n🧹 EXTRACTING JSON FROM RESPONSE...")

        // Use robust extraction
        guard let cleanJSON = extractJSON(from: jsonString) else {
            print("❌ Could not extract JSON from response")
            print("First 500 chars: \(String(jsonString.prefix(500)))")
            throw PromptEngineError.invalidJSON("Could not extract JSON from response")
        }

        // SHOW THE ENTIRE JSON
        print("\n📋 EXTRACTED JSON:")
        print(String(repeating: "=", count: 80))
        print(cleanJSON)
        print(String(repeating: "=", count: 80))
        print("Total length: \(cleanJSON.count) characters\n")

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            print("❌ Could not convert to UTF-8 data")
            throw PromptEngineError.invalidJSON("Could not convert response to UTF-8 data")
        }

        print("✅ Converted to Data: \(jsonData.count) bytes")

        // TRY TO PARSE AS GENERIC JSON FIRST TO SEE STRUCTURE
        print("\n🔍 ATTEMPTING GENERIC JSON PARSE TO SEE STRUCTURE...")
        if let genericJSON = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            print("✅ Valid JSON structure detected")
            print("Root keys: \(genericJSON.keys.sorted().joined(separator: ", "))")
            
            if let beats = genericJSON["beats"] as? [[String: Any]] {
                print("Beats array count: \(beats.count)")
                for (index, beat) in beats.enumerated() {
                    print("\nBeat \(index + 1) keys: \(beat.keys.sorted().joined(separator: ", "))")
                }
            }
        } else {
            print("❌ NOT VALID JSON - Can't even parse as generic object")
            print("\n🔍 FINDING JSON ERROR POSITION...")
            
            // Try to find where it breaks
            for i in stride(from: cleanJSON.count, through: 100, by: -100) {
                let substring = String(cleanJSON.prefix(i))
                if let data = substring.data(using: .utf8),
                   let _ = try? JSONSerialization.jsonObject(with: data) {
                    print("✅ JSON is valid up to character \(i)")
                    print("Problem likely after character \(i)")
                    if i + 100 < cleanJSON.count {
                        let startIndex = cleanJSON.index(cleanJSON.startIndex, offsetBy: i)
                        let endIndex = cleanJSON.index(cleanJSON.startIndex, offsetBy: min(i + 100, cleanJSON.count))
                        print("Problem area: \(cleanJSON[startIndex..<endIndex])")
                    }
                    break
                }
            }
            
            throw PromptEngineError.invalidJSON("JSON syntax error - see debug output above")
        }
        
        print("\n🔬 ATTEMPTING TO DECODE TO BeatResponse...")
        
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(BeatResponse.self, from: jsonData)
            
            print("✅ BEAT JSON DECODED SUCCESSFULLY!")
            print("Section ID: \(response.sectionId)")
            print("Section Role: \(response.sectionRole)")
            print("Beat Count: \(response.beatCount)")
            print("Beats found: \(response.beats.count)")
            
            // Validate response
            let errors = validateBeatResponse(response)
            if !errors.isEmpty {
                print("\n⚠️ VALIDATION WARNINGS:")
                for error in errors {
                    print("  - \(error)")
                }
            }
            
            return response
            
        } catch let DecodingError.keyNotFound(key, context) {
            print("\n❌ BEAT KEY NOT FOUND ERROR")
            print("Missing key: '\(key.stringValue)'")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            throw PromptEngineError.invalidJSON("Missing key: \(key.stringValue)")
            
        } catch let DecodingError.typeMismatch(type, context) {
            print("\n❌ BEAT TYPE MISMATCH ERROR")
            print("Expected type: \(type)")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            
            throw PromptEngineError.invalidJSON("Type mismatch - expected \(type)")
            
        } catch let DecodingError.dataCorrupted(context) {
            print("\n❌ BEAT DATA CORRUPTED ERROR")
            print("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("Context: \(context.debugDescription)")
            print("Underlying error: \(String(describing: context.underlyingError))")
            
            throw PromptEngineError.invalidJSON("Data corrupted")
            
        } catch {
            print("\n❌ UNKNOWN BEAT DECODING ERROR")
            print("Error type: \(type(of: error))")
            print("Error: \(error)")
            
            throw PromptEngineError.parsingFailed("Decoder error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Timestamp Calculation

    func calculateTimestamps(response: BeatResponse) throws -> SimpleBeatData {
        print("\n")
        print("========================================")
        print("⏱️ RESOLVING BEAT SENTENCE BOUNDARIES (A1b)")
        print("========================================")

        guard let transcript = video.transcript else {
            throw PromptEngineError.noTranscript
        }

        let calculator = TimestampCalculator(transcript: transcript, duration: video.duration)

        // Parse FULL transcript into sentences FIRST (same parsing as A1a)
        let allSentences = SentenceParser.parse(transcript)

        // Determine section's sentences and word boundaries
        let sentences: [String]
        let sectionStartWordIndex: Int  // Absolute word index where section starts

        if let startSentence = section.startSentenceIndex,
           let endSentence = section.endSentenceIndex,
           startSentence >= 0 && endSentence < allSentences.count && startSentence <= endSentence {
            // Extract sentences by index - NO re-parsing, same sentences as A1a
            sentences = Array(allSentences[startSentence...endSentence])
            print("📐 A1b calculateTimestamps: Using sentences [\(startSentence + 1)] to [\(endSentence + 1)] for \(section.role)")

            // Calculate absolute word offset: count words in all sentences BEFORE this section
            var wordOffset = 0
            for i in 0..<startSentence {
                wordOffset += allSentences[i].split(separator: " ").count
            }
            sectionStartWordIndex = wordOffset
        } else if let sectionStart = section.startWordIndex,
                  let sectionEnd = section.endWordIndex {
            // Fallback: no sentence boundaries, use word boundaries (legacy data)
            print("⚠️ A1b calculateTimestamps: No sentence boundaries for \(section.role), falling back to word extraction")
            let allWords = transcript.split(separator: " ").map(String.init)
            let sectionWords = Array(allWords[sectionStart...min(sectionEnd, allWords.count - 1)])
            let sectionTranscript = sectionWords.joined(separator: " ")
            sentences = SentenceParser.parse(sectionTranscript)
            sectionStartWordIndex = sectionStart
        } else {
            throw PromptEngineError.invalidJSON("Section has no word or sentence boundaries")
        }

        let sentenceCount = sentences.count

        // DEBUG: Show all sentences in this section
        print("\n🔎 DEBUG: Section sentences array (\(sentenceCount) total):")
        for (i, sentence) in sentences.enumerated() {
            let preview = sentence.count > 80 ? String(sentence.prefix(80)) + "..." : sentence
            print("  [\(i + 1)] \(preview)")
        }

        print("\n📊 Section Stats:")
        print("Section start word index: \(sectionStartWordIndex)")
        print("Section sentences: \(sentenceCount)")
        print("Words per second: \(calculator.wordsPerSecond)")

        // Log boundary sentences from response
        print("\n🔍 Processing \(response.beats.count) beats with sentence boundaries...")
        print("🔎 DEBUG: LLM response details:")
        for (index, beat) in response.beats.enumerated() {
            let textPreview = beat.text.count > 50 ? String(beat.text.prefix(50)) + "..." : beat.text
            if let boundary = beat.boundarySentence {
                print("  Beat \(index + 1) (\(beat.type)): boundarySentence=\(boundary)")
                print("    LLM text: \"\(textPreview)\"")
            } else {
                print("  Beat \(index + 1) (\(beat.type)): boundarySentence=null (final)")
                print("    LLM text: \"\(textPreview)\"")
            }
        }

        // Build SimpleBeat array from sentence boundaries
        // CRITICAL: Word indexes are computed FROM the extracted text, not from pre-computed ranges
        var beatsWithTimestamps: [SimpleBeat] = []
        var currentStartSentence = 0  // 0-indexed
        var currentWordPosition = sectionStartWordIndex  // Track cumulative word position

        print("\n🔍 Converting sentence boundaries to beats (sentence-first approach):")
        for (index, beatItem) in response.beats.enumerated() {
            // Determine end sentence (convert from 1-indexed to 0-indexed)
            let endSentence: Int
            if let boundary = beatItem.boundarySentence {
                endSentence = boundary - 1  // Convert 1-indexed to 0-indexed
            } else {
                endSentence = sentenceCount - 1  // Last beat goes to end
            }

            // Validate sentence range
            guard currentStartSentence < sentenceCount && endSentence < sentenceCount && currentStartSentence <= endSentence else {
                print("  ⚠️ Invalid sentence range for beat \(index + 1): \(currentStartSentence) to \(endSentence)")
                continue
            }

            // STEP 1: Extract text from sentences (this is the SOURCE OF TRUTH)
            let beatSentences = sentences[currentStartSentence...endSentence]
            let computedBeatText = beatSentences.joined(separator: " ")

            // STEP 2: Compute word indexes FROM the actual text we just extracted
            let beatWordCount = computedBeatText.split(separator: " ").count
            let absoluteStart = currentWordPosition
            let absoluteEnd = currentWordPosition + beatWordCount - 1

            // STEP 3: Advance word position for next beat
            currentWordPosition = absoluteEnd + 1

            let startTime = calculator.calculateTimestampFromWordIndex(absoluteStart)
            let endTime = calculator.calculateTimestampFromWordIndex(absoluteEnd)

            // Derive boundaryText from the actual boundary sentence (for downstream compatibility)
            let boundaryText = beatItem.boundarySentence != nil ? sentences[endSentence] : nil

            // DEBUG: Show what sentences are being joined for this beat
            print("\n🔎 DEBUG: Beat \(index + 1) text assembly:")
            print("  Extracting sentences[\(currentStartSentence)...\(endSentence)] (0-indexed)")
            print("  That's sentences [\(currentStartSentence + 1)] to [\(endSentence + 1)] (1-indexed)")
            for (j, sent) in beatSentences.enumerated() {
                let preview = sent.count > 60 ? String(sent.prefix(60)) + "..." : sent
                print("    → Sentence \(currentStartSentence + j + 1): \"\(preview)\"")
            }
            print("  Beat text (\(beatWordCount) words): \"\(String(computedBeatText.prefix(80)))...\"")
            print("  Word range (computed from text): \(absoluteStart) - \(absoluteEnd)")

            print("\nBeat \(index + 1): \(beatItem.beatId)")
            print("  Type: \(beatItem.type)")
            print("  MoveKey: \(beatItem.moveKey)")
            print("  Sentence range: [\(currentStartSentence + 1)] to [\(endSentence + 1)]")
            print("  Word range: \(absoluteStart) - \(absoluteEnd)")
            print("  Time: \(formatSeconds(startTime)) - \(formatSeconds(endTime))")
            if let bt = boundaryText {
                print("  Boundary text: \"\(bt.prefix(50))...\"")
            }

            let beat = SimpleBeat(
                beatId: beatItem.beatId,
                type: beatItem.type,
                timeRange: TimeRange(start: startTime, end: endTime),
                text: computedBeatText,  // Text from sentences (SOURCE OF TRUTH)
                startWordIndex: absoluteStart,  // Computed FROM the text
                endWordIndex: absoluteEnd,  // Computed FROM the text
                stance: beatItem.stance,
                tempo: beatItem.tempo,
                formality: beatItem.formality,
                questionCount: beatItem.questionCount,
                containsAnchor: beatItem.containsAnchor,
                anchorText: beatItem.anchorText,
                anchorFunction: beatItem.anchorFunction,
                proofMode: beatItem.proofMode,
                moveKey: beatItem.moveKey,
                sectionId: beatItem.sectionId,
                boundaryText: boundaryText,
                matchConfidence: 1.0  // Deterministic lookup = 100% confidence
            )

            beatsWithTimestamps.append(beat)

            // Next beat starts at the sentence after this one ends
            currentStartSentence = endSentence + 1
        }

        print("\n✅ All beat boundaries resolved from sentence numbers")

        // Validate contiguity
        var validationIssues: [String] = []
        for i in 0..<(beatsWithTimestamps.count - 1) {
            let current = beatsWithTimestamps[i]
            let next = beatsWithTimestamps[i + 1]
            if current.endWordIndex + 1 != next.startWordIndex {
                validationIssues.append("Gap between beat \(i + 1) and \(i + 2): word \(current.endWordIndex) to \(next.startWordIndex)")
            }
        }
        if !validationIssues.isEmpty {
            print("\n⚠️ Validation Issues:")
            for issue in validationIssues {
                print("  \(issue)")
            }
        }

        // Create SimpleBeatData with new fields
        let beatData = SimpleBeatData(
            sectionId: response.sectionId,
            sectionRole: response.sectionRole,
            beatCount: response.beatCount,
            beats: beatsWithTimestamps
        )

        print("\n========================================")
        print("✅ BEAT SENTENCE BOUNDARY RESOLUTION COMPLETE")
        print("========================================\n")

        return beatData
    }
    
    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
