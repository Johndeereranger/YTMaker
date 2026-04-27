//
//  AnalysisStatus.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/21/26.
//


// MARK: - Analysis Status Models

struct AnalysisStatus {
    let videoId: String
    let channelId: String
    let alignment: AlignmentData?  // nil if A1a not complete
    let sectionStatuses: [SectionAnalysisStatus]
    
    var a1aComplete: Bool {
        alignment != nil
    }
    
    var hasIncompleteWork: Bool {
        !a1aComplete || sectionStatuses.contains { !$0.isComplete }
    }
    
    var isFullyComplete: Bool {
        a1aComplete && sectionStatuses.allSatisfy { $0.isComplete }
    }
    
    var nextIncompleteStep: String {
        if !a1aComplete { return "A1a: Structure Analysis" }
        if let section = sectionStatuses.first(where: { !$0.isComplete }) {
            if !section.a1bComplete {
                return "Section \(section.sectionIndex + 1): Beat Extraction"
            } else {
                return "Section \(section.sectionIndex + 1), Beat \(section.completedBeats + 1)"
            }
        }
        return "Complete"
    }
    
    var totalMissingBeats: Int {
        sectionStatuses.reduce(0) { $0 + $1.incompleteBeatIndices.count }
    }
}

struct SectionAnalysisStatus: Identifiable {
    var id: String { section.id }
    let section: SectionData
    let sectionIndex: Int
    let beatDocs: [BeatDoc]
    
    var a1bComplete: Bool {
        !beatDocs.isEmpty
    }
    
    var totalBeats: Int {
        beatDocs.count
    }
    
    var completedBeats: Int {
        beatDocs.filter { $0.enrichmentLevel == "a1c" }.count
    }
    
    var isComplete: Bool {
        a1bComplete && completedBeats == totalBeats
    }
    var incompleteBeatIndices: [Int] {
        beatDocs.enumerated()
            .filter { $0.element.enrichmentLevel != "a1c" }
            .map { $0.offset }
    }
}

enum ReprocessTarget {
    case a1a
    case section(String)  // sectionId
    case beat(String, String)  // sectionId, beatId
}
