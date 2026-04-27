//
//  AIAnalysisJSON.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/6/26.
//
import Foundation

struct AIAnalysisJSON: Codable {
    struct SectionAnalysis: Codable {
        let sectionNumber: Int
        let sourceTitle: String
        let aiTitle: String
        let aiSummary: String
        let aiStrategicPurpose: String
        let aiMechanism: String
        let aiInputsRecipe: String
        let aiBSFlags: String
        let aiArchetype: String
    }
    let sections: [SectionAnalysis]
}
