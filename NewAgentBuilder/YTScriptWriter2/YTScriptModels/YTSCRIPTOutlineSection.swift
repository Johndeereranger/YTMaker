//
//  YTSCRIPTOutlineSection.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/9/25.
//
import SwiftUI

// MARK: - Outline Section
struct YTSCRIPTOutlineSection2: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var orderIndex: Int
    var targetWordCount: Int?  // nil = use default
    var bulletPoints: [String] = []
    var rawSpokenText: String = ""
    var polishedText: String = ""
    
    var sectionVersions: [YTSCRIPTSectionVersion] = []
    var currentVersionIndex: Int = -1
    var appliedHacks: [String] = []  // IDs like "hack_13", "hack_14", "storyloop"
    var storyLoopContext: String = ""
    var storyLoopReveal: String = ""
    var revealExceedsExpectations: Bool = false
    var isArchived: Bool = false
    
    init(
        id: UUID = UUID(),
        name: String,
        orderIndex: Int,
        targetWordCount: Int? = nil,
        bulletPoints: [String] = [],
        rawSpokenText: String = "",
        polishedText: String = ""
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.targetWordCount = targetWordCount
        self.bulletPoints = bulletPoints
        self.rawSpokenText = rawSpokenText
        self.polishedText = polishedText
    }
    
    // Default word counts
    static func defaultWordCount(for name: String) -> Int {
        switch name.lowercased() {
        case let n where n.contains("hook") || n.contains("intro"):
            return 350
        case let n where n.contains("outro"):
            return 150
        default:
            return 450  // Points
        }
    }
    
    var currentVersion: YTSCRIPTSectionVersion? {
        guard currentVersionIndex >= 0 && currentVersionIndex < sectionVersions.count else { return nil }
        return sectionVersions[currentVersionIndex]
    }
    
    var effectiveWordCount: Int {
        targetWordCount ?? YTSCRIPTOutlineSection2.defaultWordCount(for: name)
    }
    
    var currentWordCount: Int {
        if isArchived {
               return 0
           }
        // Priority 1: Count from parsed sentences in current version (most accurate)
        if currentVersionIndex >= 0,
           currentVersionIndex < sectionVersions.count {
            let currentVersion = sectionVersions[currentVersionIndex]
            if !currentVersion.sentences.isEmpty {
                return currentVersion.sentences.reduce(0) { $0 + $1.text.split(separator: " ").count }
            }
        }
        
        // Priority 2: Fallback to polishedText/rawSpokenText (legacy support)
        return polishedText.isEmpty ? rawSpokenText.wordCount : polishedText.wordCount
    }
}
