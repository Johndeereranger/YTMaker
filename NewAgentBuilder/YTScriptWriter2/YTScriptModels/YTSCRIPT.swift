//
//  YTSCRIPT.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/5/25.
//


import Foundation
import Observation

// MARK: - Top-Level Script
@Observable
final class YTSCRIPT: Identifiable, Codable,  Hashable {
    let id: UUID
    
    // Meta
    var title: String
    var createdAt: Date
    var writingStyle: WritingStyle = .kallaway
    var lastModified: Date
    var status: String  // "draft", "brainDump", "outlining", "scripting", "ready"
    var sourceTopicId: String?

    // Mode Selection (Phase 3.1)
    var selectedChannelId: String?
    var selectedStyleProfileId: String?

    // Global timing
    var targetMinutes: Double = 12.0
    var wordsPerMinute: Double = 165.0
    //WPM 155 = 2.58 WPS
    //WPM 166 = 2.78 WPS
    
    // 1. Mission
    var objective: String = ""
    var targetEmotion: String = "surprise"
    var audienceNotes: String = ""
    
    // 2. Brain Dump
    var brainDumpRaw: String = ""
    var points: [YTSCRIPTPoint] = []
    
    // 3. Packaging
    var packaging: YTSCRIPTPackaging?
    
    // 4. Outline
   // var outlineBlocks: [YTSCRIPTOutlineBlock] = []
   
    
    // 5. Script Sections
    var sections: [YTSCRIPTSection] = []
    
    var generatedAngles: [YTSCRIPTAngleOption] = []
    var selectedAngleId: Int? = nil
    var manualAngle: String = ""
    
    var researchPoints: [YTSCRIPTResearchPoint] = []  // Step 2: flat collection
       var outlineSections: [YTSCRIPTOutlineSection2] = [] 
    
    // MARK: - Computed
    var targetTotalWords: Int {
        Int(targetMinutes * wordsPerMinute)
    }

    
    var currentTotalWords: Int {
        outlineSections
            .filter { !$0.isArchived }  // ← Skip archived sections
            .reduce(0) { total, section in
                total + section.currentWordCount
            }
    }
    
    var estimatedMinutes: Double {
        guard wordsPerMinute > 0 else { return 0 }
        return Double(currentTotalWords) / wordsPerMinute
    }
    
    var percentComplete: Double {
        guard targetTotalWords > 0 else { return 0 }
        return min(100, Double(currentTotalWords) / Double(targetTotalWords) * 100)
    }
    
    // MARK: - Init
    // MARK: - Init
    init(
        id: UUID = UUID(),
        title: String = "Untitled Script",
        createdAt: Date = Date(),
        sourceTopicId: String? = nil  // ← ADD THIS
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastModified = createdAt
        self.status = "draft"
        self.sourceTopicId = sourceTopicId  // ← ADD THIS
    }
    
    static func == (lhs: YTSCRIPT, rhs: YTSCRIPT) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Brain Dump Point
struct YTSCRIPTPoint: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var tag: String  // "shock", "pain", "visual", etc.
    var shockScore: Int  // 0-100
    var isKeeper: Bool
    
    init(
        id: UUID = UUID(),
        text: String,
        tag: String = "fact",
        shockScore: Int = 0,
        isKeeper: Bool = false
    ) {
        self.id = id
        self.text = text
        self.tag = tag
        self.shockScore = shockScore
        self.isKeeper = isKeeper
    }
}

// MARK: - Packaging
struct YTSCRIPTPackaging: Codable {
    var chosenAngleTitle: String
    var chosenHook: String
    var notes: String
    var titleIdeas: [String]
    
    init(
        chosenAngleTitle: String = "",
        chosenHook: String = "",
        notes: String = "",
        titleIdeas: [String] = []
    ) {
        self.chosenAngleTitle = chosenAngleTitle
        self.chosenHook = chosenHook
        self.notes = notes
        self.titleIdeas = titleIdeas
    }
}

// MARK: - Angle Option
struct YTSCRIPTAngleOption: Codable, Hashable, Identifiable {
    let id: Int
    let angleStatement: String
    let nukePoint: String
    let hookType: String
    let whyItMatters: String
    let supportingPoints: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case angleStatement = "angle_statement"
        case nukePoint = "nuke_point"
        case hookType = "hook_type"
        case whyItMatters = "why_it_matters"
        case supportingPoints = "supporting_points"
    }
}

//// MARK: - Outline Block
//struct YTSCRIPTOutlineBlock: Identifiable, Codable, Hashable {
//    let id: UUID
//    var name: String
//    var orderIndex: Int
//    var targetSeconds: Double
//    
//    // Planning
//    var what: String
//    var why: String
//    var proof: String
//    var rehook: String
//    var visualNotes: String
//    
//    init(
//        id: UUID = UUID(),
//        name: String = "New Section",
//        orderIndex: Int = 0,
//        targetSeconds: Double = 60,
//        what: String = "",
//        why: String = "",
//        proof: String = "",
//        rehook: String = "",
//        visualNotes: String = ""
//    ) {
//        self.id = id
//        self.name = name
//        self.orderIndex = orderIndex
//        self.targetSeconds = targetSeconds
//        self.what = what
//        self.why = why
//        self.proof = proof
//        self.rehook = rehook
//        self.visualNotes = visualNotes
//    }
//}

// MARK: - Script Section
struct YTSCRIPTSection: Identifiable, Codable, Hashable {
    let id: UUID
    var outlineBlockID: UUID?
    var label: String
    var rawSpoken: String
    var versions: [YTSCRIPTSectionVersion]
    var activeVersionIndex: Int
    
    init(
        id: UUID = UUID(),
        outlineBlockID: UUID? = nil,
        label: String,
        rawSpoken: String = "",
        versions: [YTSCRIPTSectionVersion] = [],
        activeVersionIndex: Int = -1
    ) {
        self.id = id
        self.outlineBlockID = outlineBlockID
        self.label = label
        self.rawSpoken = rawSpoken
        self.versions = versions
        self.activeVersionIndex = activeVersionIndex
    }
    
    var activeVersion: YTSCRIPTSectionVersion? {
        guard activeVersionIndex >= 0, activeVersionIndex < versions.count else { return nil }
        return versions[activeVersionIndex]
    }
    
    var currentContent: String {
        activeVersion?.polishedText ?? rawSpoken  // Changed from .content to .polishedText
    }
    
    var currentWordCount: Int {
        currentContent.split(separator: " ").count
    }
    
}

//struct YTSCRIPTSectionVersion: Identifiable, Codable, Hashable {
//    let id: UUID
//    var content: String
//    var createdAt: Date
//    var note: String
//    
//    init(
//        id: UUID = UUID(),
//        content: String,
//        createdAt: Date = Date(),
//        note: String = ""
//    ) {
//        self.id = id
//        self.content = content
//        self.createdAt = createdAt
//        self.note = note
//    }
//    
//    var wordCount: Int {
//        content.wordCount
//    }
//}

// MARK: - Word Count Helper
extension String {
    var wordCount: Int {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

enum WritingStyle: String, Codable, CaseIterable {
    case kallaway = "Kallaway Framework"
    case derrick = "Derrick"

    
    var description: String {
        switch self {
        case .kallaway:
            return "7-part structure (Name It → Compress → Simplify → Why → Authority → Example → Tactical)"
        case .derrick:
            return "Personal journey with high ownership density"

        }
    }
    
    var guidelines: [String] {
        switch self {
        case .kallaway:
            return ["But/Therefore", "Story Loops", "7-Part Structure", "Sentence Rhythm"]
        case .derrick:
            return ["Ownership Density", "Named Specifics", "Vulnerability Moments", "Time Investment Signals"]

        }
    }
}


// MARK: - Kallaway Part Enum
enum KallawayPart: String, Codable, CaseIterable {
    case nameIt = "nameIt"
    case compressIt = "compressIt"
    case simplifyIt = "simplifyIt"
    case whyItMatters = "whyItMatters"
    case authorityProof = "authorityProof"
    case yourExample = "yourExample"
    case tacticalApplication = "tacticalApplication"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .nameIt: return "Part 1: NAME IT"
        case .compressIt: return "Part 2: COMPRESS IT"
        case .simplifyIt: return "Part 3: SIMPLIFY IT"
        case .whyItMatters: return "Part 4: WHY IT MATTERS"
        case .authorityProof: return "Part 5: AUTHORITY PROOF"
        case .yourExample: return "Part 6: YOUR EXAMPLE"
        case .tacticalApplication: return "Part 7: TACTICAL APPLICATION"
        case .unknown: return "Uncategorized"
        }
    }
    
    var color: String {
        switch self {
        case .nameIt: return "purple"
        case .compressIt: return "blue"
        case .simplifyIt: return "green"
        case .whyItMatters: return "orange"
        case .authorityProof: return "red"
        case .yourExample: return "cyan"
        case .tacticalApplication: return "indigo"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Update YTSCRIPTOutlineSentence
struct YTSCRIPTOutlineSentence: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var orderIndex: Int
    var part: KallawayPart  // ← ADD THIS
    var isFlagged: Bool = false
    
    init(id: UUID = UUID(), text: String, orderIndex: Int, part: KallawayPart = .unknown) {
        self.id = id
        self.text = text
        self.orderIndex = orderIndex
        self.part = part
    }
}
