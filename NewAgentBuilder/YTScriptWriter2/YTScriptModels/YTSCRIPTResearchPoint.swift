//
//  YTSCRIPTResearchPoint.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/6/25.
//
import SwiftUI

// MARK: - Research Point (flat collection)
struct YTSCRIPTResearchPoint: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var rawNotes: String
    var visualNotes: String
    var polishedVersions: [YTSCRIPTPointVersion]
    var activeVersionIndex: Int  // -1 = no polished version
    
    init(
        id: UUID = UUID(),
        title: String,
        rawNotes: String = "",
        visualNotes: String = "",
        polishedVersions: [YTSCRIPTPointVersion] = [],
        activeVersionIndex: Int = -1
    ) {
        self.id = id
        self.title = title
        self.rawNotes = rawNotes
        self.visualNotes = visualNotes
        self.polishedVersions = polishedVersions
        self.activeVersionIndex = activeVersionIndex
    }
    
    var activeVersion: YTSCRIPTPointVersion? {
        guard activeVersionIndex >= 0, activeVersionIndex < polishedVersions.count else { return nil }
        return polishedVersions[activeVersionIndex]
    }
    
    var currentContent: String {
        activeVersion?.content ?? rawNotes
    }
    
    var currentWordCount: Int {
        currentContent.wordCount
    }
}

struct YTSCRIPTPointVersion: Identifiable, Codable, Hashable {
    let id: UUID
    var content: String
    var createdAt: Date
    var note: String
    var promptUsed: String
    
    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        note: String = "",
        promptUsed: String = ""
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.note = note
        self.promptUsed = promptUsed
    }
    
    var wordCount: Int {
        content.wordCount
    }
}

//// MARK: - Outline Section (organized structure)
//struct YTSCRIPTOutlineSection: Identifiable, Codable, Hashable {
//    let id: UUID
//    var sectionType: String  // "hook", "intro", "body", "outro"
//    var name: String  // "Hook", "Point 1", etc.
//    var orderIndex: Int
//    var targetSeconds: Double
//    
//    // Content source
//    var contentType: String  // "linked" (from research point), "custom" (written here), "empty"
//    var linkedResearchPointID: UUID?  // If linked to a research point
//    var customContent: String  // If writing custom content
//    
//    // Story elements (for custom content)
//    var what: String
//    var why: String
//    var proof: String
//    var rehook: String
//    
//    init(
//        id: UUID = UUID(),
//        sectionType: String,
//        name: String,
//        orderIndex: Int,
//        targetSeconds: Double = 60,
//        contentType: String = "empty",
//        linkedResearchPointID: UUID? = nil,
//        customContent: String = "",
//        what: String = "",
//        why: String = "",
//        proof: String = "",
//        rehook: String = ""
//    ) {
//        self.id = id
//        self.sectionType = sectionType
//        self.name = name
//        self.orderIndex = orderIndex
//        self.targetSeconds = targetSeconds
//        self.contentType = contentType
//        self.linkedResearchPointID = linkedResearchPointID
//        self.customContent = customContent
//        self.what = what
//        self.why = why
//        self.proof = proof
//        self.rehook = rehook
//    }
//    
//    func targetWords(wpm: Double) -> Int {
//        Int(targetSeconds * wpm / 60.0)
//    }
//}
