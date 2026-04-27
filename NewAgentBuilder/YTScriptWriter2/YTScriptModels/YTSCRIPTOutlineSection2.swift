//
//  YTSCRIPTOutlineSection2.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/9/25.
//
import SwiftUI


// MARK: - Section Version (COMBINED - works for both old and new)
struct YTSCRIPTSectionVersion: Codable, Identifiable, Hashable {
    let id: UUID
    
    // OLD SYSTEM properties (for YTSCRIPTSection)
    var content: String?
    var createdAt: Date?
    var note: String?
    
    // NEW SYSTEM properties (for YTSCRIPTOutlineSection2)
    var timestamp: Date?
    var polishedText: String?
    var sentences: [YTSCRIPTOutlineSentence]
    var wordCount: Int
    
    init(
        id: UUID = UUID(),
        content: String? = nil,
        createdAt: Date? = nil,
        note: String? = nil,
        timestamp: Date? = nil,
        polishedText: String? = nil,
        sentences: [YTSCRIPTOutlineSentence] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.note = note
        self.timestamp = timestamp ?? createdAt ?? Date()
        self.polishedText = polishedText ?? content
        self.sentences = sentences
        self.wordCount = (polishedText ?? content ?? "").split(separator: " ").count
    }
}

struct YTSCRIPTSectionSentence: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var orderIndex: Int
    
    init(id: UUID = UUID(), text: String, orderIndex: Int) {
        self.id = id
        self.text = text
        self.orderIndex = orderIndex
    }
}
