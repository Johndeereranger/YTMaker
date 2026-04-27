//
//  ExportedPattern.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//


import Foundation

/// A pattern that has been exported for reuse in the playbook
struct ExportedPattern: Identifiable, Codable, Equatable {
    let id: UUID
    
    // Video context (IDs are source of truth)
    let videoId: String
    var videoTitle: String
    let channelId: String
    var channelName: String?
    
    // Section context
    var sectionTitle: String
    
    // Pattern details
    let patternType: PatternType
    let sentenceText: String  // Combined text from all sentences
    var note: String?
    
    // Creator context
    let creatorId: String  // Source of truth - never changes
    var creatorName: String?  // Can change, not critical
    
    // Metadata
    let exportedDate: Date
    
    // Original pattern reference (for deduplication)
    let originalPatternId: UUID
    
    init(
        id: UUID = UUID(),
        videoId: String,
        videoTitle: String,
        channelId: String,
        channelName: String?,
        sectionTitle: String,
        patternType: PatternType,
        sentenceText: String,
        note: String?,
        creatorId: String,
        creatorName: String?,
        exportedDate: Date = Date(),
        originalPatternId: UUID
    ) {
        self.id = id
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.channelId = channelId
        self.channelName = channelName
        self.sectionTitle = sectionTitle
        self.patternType = patternType
        self.sentenceText = sentenceText
        self.note = note
        self.creatorId = creatorId
        self.creatorName = creatorName
        self.exportedDate = exportedDate
        self.originalPatternId = originalPatternId
    }
}