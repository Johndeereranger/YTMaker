//
//  AlignmentData.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/16/26.
//


import Foundation

// MARK: - Alignment Data (A1a Output)
// MARK: - Alignment Data (A1a Output)
struct AlignmentData: Codable, Identifiable {
    var id = UUID()
    var videoId: String
    var channelId: String
    var videoSummary: String
    var sections: [SectionData]
    var logicSpine: LogicSpineData
    var bridgePoints: [BridgePoint]
    var extractionDate: Date
    var validationStatus: ValidationStatus
    var validationIssues: [ValidationIssue]?
    
    init(videoId: String, channelId: String, videoSummary: String, sections: [SectionData],
         logicSpine: LogicSpineData, bridgePoints: [BridgePoint]) {
        self.videoId = videoId
        self.channelId = channelId
        self.videoSummary = videoSummary
        self.sections = sections
        self.logicSpine = logicSpine
        self.bridgePoints = bridgePoints
        self.extractionDate = Date()
        self.validationStatus = .pending
    }
}

// MARK: - Nested Section (for sponsorships/CTAs inside content sections)
struct NestedSection: Codable, Identifiable {
    var id: String { "\(role)_\(startSentence)" }
    var role: String              // SPONSORSHIP, CTA
    var startSentence: Int        // 1-indexed sentence number where nested section starts
    var endSentence: Int          // 1-indexed sentence number where nested section ends
}

struct SectionData: Codable, Identifiable {
    var id: String

    // Legacy (optional - old data has this)
    var timeRange: TimeRange?

    // Sentence boundaries (from A1a boundarySentence - 0-indexed)
    var startSentenceIndex: Int?
    var endSentenceIndex: Int?

    // Word boundaries (computed from sentence boundaries)
    var startWordIndex: Int?
    var endWordIndex: Int?

    var role: String  // HOOK, SETUP, EVIDENCE, TURN, PAYOFF, CTA, SPONSORSHIP
    var goal: String
    var logicSpineStep: String

    // Nested sections (e.g., SPONSORSHIP inside EVIDENCE)
    var nestedSections: [NestedSection]?

    // Boundary resolution metadata (for debugging/auditing)
    var boundaryText: String?       // The text of the boundary sentence
    var matchConfidence: Double?    // How confident the boundary match was (0-1)

    // Computed helpers
    var hasSentenceBoundaries: Bool {
        startSentenceIndex != nil && endSentenceIndex != nil
    }

    var hasWordBoundaries: Bool {
        startWordIndex != nil && endWordIndex != nil
    }

    // Computed time range from word boundaries
    func estimatedTimeRange(for video: YouTubeVideo) -> TimeRange? {
        guard let start = startWordIndex, let end = endWordIndex,
              let transcript = video.transcript else { return nil }

        let durationSeconds = parseDurationString(video.duration)
        guard durationSeconds > 0 else { return nil }

        let totalWords = transcript.split(separator: " ").count
        guard totalWords > 0 else { return nil }

        let wordsPerSecond = Double(totalWords) / Double(durationSeconds)
        guard wordsPerSecond > 0 else { return nil }

        let startSeconds = Int(Double(start) / wordsPerSecond)
        let endSeconds = Int(Double(end) / wordsPerSecond)

        return TimeRange(start: startSeconds, end: endSeconds)
    }

    // Helper to parse ISO 8601 duration string
    private func parseDurationString(_ duration: String) -> Int {
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
            return hours * 3600 + minutes * 60 + seconds
        }

        // Try "MM:SS" or "HH:MM:SS" format
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

        return 0
    }
}

struct TimeRange: Codable, Hashable {
    var start: Int  // seconds
    var end: Int    // seconds
}

struct LogicSpineData: Codable {
    var chain: [String]
    var causalLinks: [CausalLink]
}

struct CausalLink: Codable, Identifiable {
    var id = UUID()
    var from: String
    var to: String
    var connection: String
    
    enum CodingKeys: String, CodingKey {
        case from, to, connection
    }
}

struct BridgePoint: Codable, Identifiable {
    var id = UUID()
    var text: String
    var belongsTo: [String]
    var timestamp: Int
    
    enum CodingKeys: String, CodingKey {
        case text, belongsTo, timestamp
    }
}

enum ValidationStatus: String, Codable {
    case pending
    case passed
    case failed
    case needsReview
}

struct ValidationIssue: Codable, Identifiable {
    var id = UUID()
    var severity: Severity
    var type: IssueType
    var message: String
    
    enum CodingKeys: String, CodingKey {
        case severity, type, message
    }
    
    enum Severity: String, Codable {
        case error
        case warning
    }
    
    enum IssueType: String, Codable {
        case sectionCount
        case timeOverlap
        case timeGap
        case incompleteSpine
        case illogicalFlow
        case beatCount
        case genericAnchor
        case missingTransition
    }
}

//// MARK: - Beat Data (A1b Output)
//struct BeatData: Codable, Identifiable {
//    var id = UUID()
//    var sectionId: String
//    var beats: [Beat]
//    var transitionOut: Transition?
//    var anchorLines: [String]
//}
//
//struct Beat: Codable, Identifiable {
//    var id = UUID()
//    var type: String  // TEASE, QUESTION, PROMISE, DATA, STORY, AUTHORITY, SYNTHESIS, TURN
//    var timeRange: TimeRange
//    var text: String
//    var function: String
//}
//
//struct Transition: Codable {
//    var type: String  // callback, direct_pivot, contrarian_flip, question_bridge
//    var bridgeSentence: String?
//}

// MARK: - Snippet Data (A2 Output)
struct SnippetData: Codable, Identifiable {
    var id = UUID()
    var videoId: String
    var channelId: String
    var sectionId: String
    var beatType: String
    var text: String
    
    // Mechanics fingerprint
    var role: String
    var intent: String
    var tempo: String
    var stance: String
    var teaseDistance: Int?
    var sentenceCount: Int
    var avgSentenceLength: Double
    var questionCount: Int
    var dataPoints: Int
    var mechanicsDescription: String
    var rhetoricalDevices: [String]
    
    // Topic fingerprint
    var primaryTopic: String
    var secondaryTopics: [String]
    var specificity: String
    var topicDescription: String
    
    // Style markers
    var vocabularyLevel: Int
    var formality: Int
    var profanity: Bool
    var humorStyle: String
    var personalVoice: Bool
    
    // Quality
    var qualityTier: QualityTier
    var qualityReasoning: String
}

enum QualityTier: String, Codable, CaseIterable {
    case canonical
    case situational
    case weak
}

// MARK: - Aggregation Data (A3 Output)
struct AggregationData: Codable, Identifiable {
    var id = UUID()
    var channelId: String
    var modes: [CreatorMode]
    var constraints: ConstraintsData
    var anchorLibrary: AnchorLibraryData
    var antiPatterns: AntiPatternsData
    var cooldownRules: CooldownRulesData
    var basedOnVideoCount: Int
    var aggregationDate: Date
}

struct CreatorMode: Codable, Identifiable {
    var id = UUID()
    var modeName: String
    var frequency: Double
    var arcStructure: [String]
    var typicalBeats: [String]
    var pacingProfile: String
    var useForContentTypes: [String]
    var exampleVideoIds: [String]
}

struct ConstraintsData: Codable {
    var sentenceCadence: SentenceCadence
    var teaseDistance: TeaseDistance
    var questionRate: QuestionRate
    var dataDensity: DataDensity
}

struct SentenceCadence: Codable {
    var avgLength: Double
    var stdDev: Double
    var shortBurstFrequency: Double
}

struct TeaseDistance: Codable {
    var avg: Int
    var max: Int
}

struct QuestionRate: Codable {
    var rhetorical: Double
    var genuine: Double
}

struct DataDensity: Codable {
    var statsPerSection: Double
    var examplesPerSection: Double
}

struct AnchorLibraryData: Codable {
    var openers: [String]
    var turns: [String]
    var proofFrames: [String]
    var closers: [String]
}

struct AntiPatternsData: Codable {
    var forbiddenPhrases: [String]
    var forbiddenStructures: [String]
    var hedgeRequirements: [String: String]
}

struct CooldownRulesData: Codable {
    var minDistance: Int
    var maxFrequency: Double
}
